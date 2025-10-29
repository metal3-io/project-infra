#Run a basic http server to expose the disk images:
docker run --name image-server --rm -d -p 80:8080 \
  -v "${QUICK_START_BASE}/disk-images:/usr/share/nginx/html" nginxinc/nginx-unprivileged
