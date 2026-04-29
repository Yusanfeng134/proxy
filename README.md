# 海外住宅代理中转

这个项目用 Docker Compose 启动一个 GOST 中转服务。国内客户端连接海外服务器，海外服务器再轮询转发到两个静态住宅 SOCKS5 上游。

## 暴露入口

- SOCKS5：`socks5://PUBLIC_USER:PUBLIC_PASS@SERVER_IP:1080`
- HTTP/HTTPS 代理：`http://PUBLIC_USER:PUBLIC_PASS@SERVER_IP:8080`
- HTTP/2 TLS 隧道：`SERVER_IP:8443`，给可运行本地 GOST 客户端的国内设备使用

所有入口都必须使用 `.env` 里的 `PUBLIC_USER` 和 `PUBLIC_PASS`。不要把没有认证的代理端口暴露到公网。

## 海外服务器部署

1. 安装 Docker 和 Docker Compose v2。
2. 把项目放到海外服务器。
3. 创建环境文件：

   ```bash
   cp .env.example .env
   nano .env
   ```

4. 修改 `.env` 里的公开访问账号、两个上游 SOCKS5 账号和 `SERVER_HOST`。
5. 生成配置、证书并启动：

   ```bash
   ./scripts/up.sh
   ```

6. 放行 TCP 端口：

   ```bash
   sudo ufw allow 1080/tcp
   sudo ufw allow 8080/tcp
   sudo ufw allow 8443/tcp
   ```

如果你的系统不用 `ufw`，在云厂商安全组和系统防火墙里放行同样的 TCP 端口。

## 国内客户端配置

普通 SOCKS5：

```text
协议: SOCKS5
服务器: SERVER_IP
端口: 1080
用户名: PUBLIC_USER
密码: PUBLIC_PASS
```

普通 HTTP/HTTPS 代理：

```text
协议: HTTP
服务器: SERVER_IP
端口: 8080
用户名: PUBLIC_USER
密码: PUBLIC_PASS
```

HTTP/2 TLS 隧道模式适合可以运行本地 GOST 的设备。先把海外服务器上的 `certs/ca.crt` 复制到国内设备，再把 `.runtime/client-h2.yml` 里的 `SERVER_HOST` 渲染成真实海外 IP 后运行：

```bash
gost -C client-h2.yml
```

之后国内软件填本地 SOCKS5：

```text
协议: SOCKS5
服务器: 127.0.0.1
端口: 11080
```

也可以用一行命令：

```bash
gost -L socks5://127.0.0.1:11080 -F "socks5+h2://PUBLIC_USER:PUBLIC_PASS@SERVER_IP:8443?secure=true&serverName=proxy.local&caFile=./ca.crt"
```

## 验证

部署前本地检查：

```bash
./scripts/validate.sh
```

海外服务器启动后检查日志：

```bash
docker compose --env-file .env logs -f gost
```

HTTP 代理出口测试：

```bash
curl -x http://PUBLIC_USER:PUBLIC_PASS@SERVER_IP:8080 https://api.ipify.org
```

SOCKS5 出口测试：

```bash
curl --socks5-hostname PUBLIC_USER:PUBLIC_PASS@SERVER_IP:1080 https://api.ipify.org
```

连续运行多次时，出口应在两个住宅代理之间轮询；如果某个上游失败，GOST 会在失败超时内临时跳过它。

## 文件说明

- `.env.example`：变量模板，可提交。
- `.env`：真实账号和端口，本地文件，不提交。
- `.runtime/gost.yml`：渲染后的服务端 GOST 配置，包含账号，不提交。
- `.runtime/client-h2.yml`：渲染后的国内本地客户端配置，包含公开入口账号，不提交。
- `certs/ca.crt`：复制到国内客户端用于校验自签证书。
- `certs/server.key` 和 `certs/ca.key`：私钥，只保存在海外服务器，不提交。

## 常用命令

```bash
./scripts/render-config.sh
./scripts/generate-certs.sh
docker compose --env-file .env up -d
docker compose --env-file .env down
docker compose --env-file .env logs -f gost
```
