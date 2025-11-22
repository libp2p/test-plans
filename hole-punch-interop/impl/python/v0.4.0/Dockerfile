FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y git build-essential iptables libgmp-dev && rm -rf /var/lib/apt/lists/*

# Upgrade pip and build tools
RUN python -m pip install --upgrade pip setuptools wheel

WORKDIR /app

# Copy only pyproject.toml first to leverage Docker cache
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

# Copy rest of the code
COPY hole_punch.py .

# Startup script for iptables + python app
COPY start.sh /start.sh
RUN chmod +x /start.sh
ENTRYPOINT ["/start.sh"]

VOLUME /results
