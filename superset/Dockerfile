# superset/Dockerfile
FROM apache/superset:latest

# Switch to root to install system dependencies
USER root

# Install system libraries required for the mysqlclient driver
RUN apt-get update && \
    apt-get install -y default-libmysqlclient-dev build-essential pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Install the MySQL python driver
RUN pip install mysqlclient

# Switch back to the superset user for security
USER superset