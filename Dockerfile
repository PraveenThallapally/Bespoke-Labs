FROM docker:24-dind

# Install dependencies
RUN apk add --no-cache \
    curl \
    bash \
    git \
    ca-certificates

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install k3d
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Set working directory
WORKDIR /app

# Copy wiki-service and wiki-chart
COPY wiki-service/ /app/wiki-service/
COPY wiki-chart/ /app/wiki-chart/

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose port
EXPOSE 8080

# Run startup script
ENTRYPOINT ["/start.sh"]
