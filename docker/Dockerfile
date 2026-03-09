FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    unzip \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir openpyxl

# Install yq (XML → JSON converter used by export.sh)
RUN curl -sL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install AWS CLI v2
RUN curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip
RUN pip install --no-cache-dir openpyxl

WORKDIR /app

# ---------------------------------------------------------------
# Copy the BE team's scripts here:
#   - export.sh      (shell script — the main runner)
#   - export.py      (python — RSS/XML → CSV parser)
#   - sites.txt      (list of sites to pull)
#   - run-export.sh  (wrapper — sets OUTPUT_DIR + uploads to S3)
# ---------------------------------------------------------------
COPY scripts/ /app/

RUN chmod +x /app/*.sh

ENTRYPOINT ["/app/run-export.sh"]
