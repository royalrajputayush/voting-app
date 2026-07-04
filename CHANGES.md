# 📝 Codebase Changes Summary

This file outlines the specific changes made to the codebase of the **Docker Sample Voting App** compared to the original repository.

---

## 📂 Summary of Modified & Added Files

```
example-voting-app-main/
├── README.md                           # [MODIFIED] Fully updated with production docs and setup steps
├── CHANGES.md                          # [NEW] Documenting codebase diffs
├── bootstrap.sh                        # [NEW] Single-command Linux/macOS kind cluster bootstrap
├── bootstrap.ps1                       # [NEW] Single-command Windows PowerShell kind cluster bootstrap
├── Makefile                            # [NEW] Target wrapper for `make demo`
├── .github/workflows/ci.yml            # [NEW] GitHub Actions CI/CD workflow for vote service
├── vote/
│   ├── app.py                          # [MODIFIED] Changed Flask runtime port to 8080
│   └── Dockerfile                      # [MODIFIED] Added non-root user (appuser) and configured port 8080
├── result/
│   ├── server.js                       # [MODIFIED] Enabled config from DATABASE_URL env variable
│   └── Dockerfile                      # [MODIFIED] Added node user (UID 1000) and configured port 8080
├── worker/
│   └── Program.cs                      # [MODIFIED] Configured DB Connection and Redis host via env variables
└── charts/voting-app/                  # [NEW] Production-ready Helm Chart
    ├── Chart.yaml                      # Chart definition metadata
    ├── values.yaml                     # Default parameters
    ├── values-dev.yaml                 # Development overrides for kind cluster
    ├── values-staging.yaml             # Staging overrides (scaling, HPA)
    └── templates/                      # Kubernetes manifests
        ├── db-secret.yaml              # Decoupled database credential Secret
        ├── db-statefulset.yaml         # Persistent StatefulSet with PVC volumes
        ├── db-service.yaml             # Internal ClusterIP DB service
        ├── db-bootstrap-job.yaml       # Hook schema configuration database job
        ├── redis-deployment.yaml       # Cache Deployment with socket health check
        ├── redis-service.yaml          # Internal ClusterIP Redis service
        ├── vote-deployment.yaml        # Non-Root Vote app Deployment with HTTP probes
        ├── vote-service.yaml           # ClusterIP service for Ingress mapping
        ├── hpa.yaml                    # CPU-utilization HPA rules for Vote app
        ├── result-deployment.yaml      # Non-Root Result app Deployment with HTTP probes
        ├── result-service.yaml         # ClusterIP service for Ingress mapping
        ├── worker-deployment.yaml      # Worker Queue Consumer Deployment with process probes
        ├── ingress.yaml                # NGINX Ingress rules with wildcard nip.io hosts
        └── networkpolicies.yaml        # Namespace-tier traffic isolation NetworkPolicies
```

---

## 🔍 Specific Code Diffs

### 1. Vote Frontend Service

#### 📄 [vote/app.py](file:///c:/Users/lenovo/Desktop/example-voting-app-main/example-voting-app-main/vote/app.py)
Changed Flask's default port from `80` to `8080` to support execution under a non-privileged user:
```diff
@@ -51,2 +51,2 @@
 if __name__ == "__main__":
-    app.run(host='0.0.0.0', port=80, debug=True, threaded=True)
+    app.run(host='0.0.0.0', port=8080, debug=True, threaded=True)
```

#### 📄 [vote/Dockerfile](file:///c:/Users/lenovo/Desktop/example-voting-app-main/example-voting-app-main/vote/Dockerfile)
Added `appuser` (UID 10001) creation, switched execution environment to that user, and updated port EXPOSE and binding configurations:
```diff
@@ -21,5 +21,11 @@
+# final defines the stage that will bundle the application for production
+FROM base AS final
+
+# Create a non-root user
+RUN groupadd -g 10001 appuser && \
+    useradd -r -u 10001 -g appuser appuser
+USER appuser
 
 # Copy our code from the current folder to the working directory inside the container
 COPY . .
 
 # Make port 8080 available for links and/or publish
-EXPOSE 80
+EXPOSE 8080
 
 # Define our command to be run when launching the container
-CMD ["gunicorn", "app:app", "-b", "0.0.0.0:80", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
+CMD ["gunicorn", "app:app", "-b", "0.0.0.0:8080", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
```

---

### 2. Result Frontend Service

#### 📄 [result/server.js](file:///c:/Users/lenovo/Desktop/example-voting-app-main/example-voting-app-main/result/server.js)
Enabled configuration injection from the environment, replacing the hardcoded connection string:
```diff
@@ -20,3 +20,3 @@
 var pool = new Pool({
-  connectionString: 'postgres://postgres:postgres@db/postgres'
+  connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@db/postgres'
 });
```

#### 📄 [result/Dockerfile](file:///c:/Users/lenovo/Desktop/example-voting-app-main/example-voting-app-main/result/Dockerfile)
Configured directory permissions, mapped port environments to `8080`, and updated execution state to use the standard non-root `node` (UID 1000) user:
```diff
@@ -19,8 +19,12 @@
 COPY . .
 
-ENV PORT=80
-EXPOSE 80
+RUN chown -R node:node /usr/local/app
+
+ENV PORT=8080
+EXPOSE 8080
+
+USER node
 
 ENTRYPOINT ["/usr/bin/tini", "--"]
 CMD ["node", "server.js"]
```

---

### 3. Worker Backend Queue Service

#### 📄 [worker/Program.cs](file:///c:/Users/lenovo/Desktop/example-voting-app-main/example-voting-app-main/worker/Program.cs)
Enabled dynamic environment variables lookup for the PostgreSQL connection string (`CONNECTION_STRING`) and Redis cache endpoint host (`REDIS_HOST`), replacing hardcoded strings:
```diff
@@ -19,2 +19,5 @@
-                var pgsql = OpenDbConnection("Server=db;Username=postgres;Password=postgres;");
-                var redisConn = OpenRedisConnection("redis");
+                var connectionString = Environment.GetEnvironmentVariable("CONNECTION_STRING") ?? "Server=db;Username=postgres;Password=postgres;";
+                var redisHost = Environment.GetEnvironmentVariable("REDIS_HOST") ?? "redis";
+
+                var pgsql = OpenDbConnection(connectionString);
+                var redisConn = OpenRedisConnection(redisHost);
                 var redis = redisConn.GetDatabase();
@@ -37,1 +40,1 @@
-                        redisConn = OpenRedisConnection("redis");
+                        redisConn = OpenRedisConnection(redisHost);
@@ -49,1 +52,1 @@
-                            pgsql = OpenDbConnection("Server=db;Username=postgres;Password=postgres;");
+                            pgsql = OpenDbConnection(connectionString);
```
