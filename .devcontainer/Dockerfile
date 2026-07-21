# Coding Agent Development Container
# Based on the official reference implementation with Java 21 support
# Multi-stage build supporting base (Claude Code), opencode, and their
# Docker-in-Docker variants (dind, opencode-dind)

ARG NODE_VERSION=22
ARG VARIANT=base

# ========================================
# BASE-COMMON STAGE (shared dependencies)
# Agent-agnostic: tools, Java.
# Agent CLIs (Claude Code, OpenCode) are added in downstream stages.
# ========================================
FROM node:${NODE_VERSION}-trixie AS base-common

ARG TZ=Europe/Helsinki

ENV TZ=${TZ} \
    DEBIAN_FRONTEND=noninteractive \
    NODE_PATH=/usr/local/lib/node_modules

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    less \
    lsb-release \
    openssh-client \
    sudo \
    nano \
    vim \
    wget \
    zsh \
    zip \
    unzip \
    screen \
    htop \
    # Firewall tools
    iptables \
    dnsutils \
    iputils-ping \
    apt-transport-https \
    # Process tools (pgrep used by the dind entrypoint to detect dockerd)
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# The container intentionally has no SSH identity — Git access to GitHub is via HTTPS
RUN git config --system url."https://github.com/".insteadOf "git@github.com:" \
 && git config --system url."https://github.com/".insteadOf "ssh://git@github.com/"

# Install Java (vendor and version configurable via build args)
# Supported vendors: temurin (default), corretto, zulu
ARG JAVA_VERSION=25
ARG JAVA_VENDOR=temurin
RUN set -eux; \
    mkdir -p /etc/apt/keyrings; \
    case "${JAVA_VENDOR}" in \
      temurin) \
        wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
          | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg; \
        echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
          > /etc/apt/sources.list.d/adoptium.list; \
        apt-get update && apt-get install -y temurin-${JAVA_VERSION}-jdk; \
        JDK_DIR=$(ls -d /usr/lib/jvm/temurin-${JAVA_VERSION}-jdk-*); \
        ;; \
      corretto) \
        wget -qO - https://apt.corretto.aws/corretto.key \
          | gpg --dearmor -o /etc/apt/keyrings/corretto.gpg; \
        echo "deb [signed-by=/etc/apt/keyrings/corretto.gpg] https://apt.corretto.aws stable main" \
          > /etc/apt/sources.list.d/corretto.list; \
        apt-get update && apt-get install -y java-${JAVA_VERSION}-amazon-corretto-jdk; \
        JDK_DIR=$(ls -d /usr/lib/jvm/java-${JAVA_VERSION}-amazon-corretto-*); \
        ;; \
      zulu) \
        wget -qO - https://repos.azul.com/azul-repo.key \
          | gpg --dearmor -o /etc/apt/keyrings/azul.gpg; \
        echo "deb [signed-by=/etc/apt/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" \
          > /etc/apt/sources.list.d/zulu.list; \
        apt-get update && apt-get install -y zulu${JAVA_VERSION}-jdk; \
        JDK_DIR=$(ls -d /usr/lib/jvm/zulu${JAVA_VERSION}-*); \
        ;; \
      *) echo "Unknown JAVA_VENDOR: ${JAVA_VENDOR}. Supported: temurin, corretto, zulu"; exit 1 ;; \
    esac; \
    ln -s "${JDK_DIR}" /usr/lib/jvm/java-active; \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-active
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Maven: FS-safe file locking for concurrent builds against the shared,
# bind-mounted ~/.m2/repository (multiple containers / worktrees in parallel).
# Container-only on purpose — host-side IntelliJ/Maven stays untouched.
ENV MAVEN_OPTS="-Daether.syncContext.named.factory=file-lock -Daether.syncContext.named.nameMapper=file-gav"

# Make npm global directories writable by the node user
# This allows Claude to self-update
RUN chown -R node:node /usr/local/lib/node_modules \
    && chown -R node:node /usr/local/bin

# Configure node user with sudo access
RUN echo "node ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node

# Create directories for the node user
RUN mkdir -p /home/node/.claude /home/node/.config/gh /commandhistory \
    && chown -R node:node /home/node /commandhistory

# Install Oh My Zsh for the node user
USER node
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Configure zsh with useful aliases
RUN echo '\n# Claude Code aliases' >> /home/node/.zshrc \
    && echo 'alias firewall-reload="sudo /usr/local/bin/init-firewall.sh"' >> /home/node/.zshrc \
    && echo 'alias firewall-status="sudo iptables -L -n -v"' >> /home/node/.zshrc \
    && echo '\n# History settings for persistent history' >> /home/node/.zshrc \
    && echo 'HISTFILE=/commandhistory/.zsh_history' >> /home/node/.zshrc \
    && echo 'HISTSIZE=10000' >> /home/node/.zshrc \
    && echo 'SAVEHIST=10000' >> /home/node/.zshrc

# ========================================
# BASE STAGE (Claude Code)
# ========================================
FROM base-common AS base

# CLAUDE_CODE_VERSION: pass "latest" (default), "stable", or a specific
# version like "2.1.126". The installer always downloads the newest binary
# and uses this value to set the active launcher target.
ARG CLAUDE_CODE_VERSION=latest
ENV CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}

USER root

# Install Claude Code via the official bash installer.
# Runs as `node` so the binary lands in /home/node/.local/share/claude/...
# with a symlink at /home/node/.local/bin/claude. We add a second symlink
# in /usr/local/bin so the CLI is on PATH for any user.
RUN if [ "${CLAUDE_CODE_VERSION}" = "latest" ]; then \
      su - node -c "curl -fsSL https://claude.ai/install.sh | bash"; \
    else \
      su - node -c "curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}"; \
    fi \
    && ln -sf /home/node/.local/bin/claude /usr/local/bin/claude

# Install Vaadin Claude Plugins
# Note: This runs non-interactively via stdin. If it fails, the plugins can be installed
# manually after container start using: /plugin marketplace add vaadin/agent-marketplace
RUN su - node -c 'echo -e "/plugin marketplace add vaadin/agent-marketplace\n/plugin install vaadin-skills@vaadin-marketplace" | claude --non-interactive' || \
    echo "Warning: Vaadin plugins could not be pre-installed. Install manually with: /plugin marketplace add vaadin/agent-marketplace"

# Copy firewall, entrypoint, and helper scripts
COPY scripts/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/init-vaadin-plugins.sh /usr/local/bin/init-vaadin-plugins.sh
COPY scripts/statusline-command.sh /usr/local/bin/statusline-command.sh
COPY claude-language-policy.md /usr/local/etc/claude-language-policy.md
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh /usr/local/bin/init-vaadin-plugins.sh /usr/local/bin/statusline-command.sh

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Switch to node user
USER node

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]

# ========================================
# OPENCODE STAGE (sst/opencode)
# ========================================
FROM base-common AS opencode

# OPENCODE_VERSION: pass "latest" (default) or a specific version like "1.14.33"
ARG OPENCODE_VERSION=latest
ENV OPENCODE_VERSION=${OPENCODE_VERSION}

USER root

# Install OpenCode via the official bash installer.
# Runs as `node` so the binary lands in /home/node/.opencode/bin/opencode,
# then symlinked into /usr/local/bin for system-wide PATH availability.
# Tar is already provided by the node:trixie base image.
RUN if [ "${OPENCODE_VERSION}" = "latest" ]; then \
      su - node -c "curl -fsSL https://opencode.ai/install | bash"; \
    else \
      su - node -c "curl -fsSL https://opencode.ai/install | bash -s -- --version ${OPENCODE_VERSION}"; \
    fi \
    && ln -sf /home/node/.opencode/bin/opencode /usr/local/bin/opencode

# Copy firewall, entrypoint, and helper scripts
COPY scripts/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY scripts/entrypoint-opencode.sh /usr/local/bin/entrypoint.sh
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace

# Switch to node user
USER node

# Set entrypoint and default command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/zsh"]

# ========================================
# DIND STAGE (Claude Code + Docker-in-Docker)
# ========================================
FROM base AS dind

USER root

# Install Docker CE and configure the daemon (shared with opencode-dind).
COPY scripts/install-docker.sh /usr/local/bin/install-docker.sh
RUN chmod +x /usr/local/bin/install-docker.sh && /usr/local/bin/install-docker.sh

# Add node user to docker group
RUN usermod -aG docker node

# Copy scripts (including the DinD entrypoint)
COPY scripts/init-firewall.sh /usr/local/bin/init-firewall.sh
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
COPY scripts/init-vaadin-plugins.sh /usr/local/bin/init-vaadin-plugins.sh
COPY scripts/statusline-command.sh /usr/local/bin/statusline-command.sh
COPY claude-language-policy.md /usr/local/etc/claude-language-policy.md
COPY allowed-domains.conf /usr/local/etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh \
             /usr/local/bin/entrypoint.sh \
             /usr/local/bin/entrypoint-dind.sh \
             /usr/local/bin/init-vaadin-plugins.sh \
             /usr/local/bin/statusline-command.sh

# Set working directory and ensure node user owns it
RUN mkdir -p /workspace && chown node:node /workspace
WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]

# ========================================
# OPENCODE-DIND STAGE (OpenCode + Docker-in-Docker)
# ========================================
# Same Docker-in-Docker setup as the `dind` stage, but on top of the OpenCode
# agent instead of Claude Code. The DinD entrypoint is agent-agnostic: it starts
# dockerd, then execs /usr/local/bin/entrypoint.sh — which the opencode stage
# already installed as the OpenCode entrypoint.
FROM opencode AS opencode-dind

USER root

# Install Docker CE and configure the daemon (shared with dind).
COPY scripts/install-docker.sh /usr/local/bin/install-docker.sh
RUN chmod +x /usr/local/bin/install-docker.sh && /usr/local/bin/install-docker.sh

# Add node user to docker group
RUN usermod -aG docker node

# Copy the DinD entrypoint (other scripts were installed by the opencode stage,
# whose entrypoint-opencode.sh already lives at /usr/local/bin/entrypoint.sh).
COPY scripts/entrypoint-dind.sh /usr/local/bin/entrypoint-dind.sh
RUN chmod +x /usr/local/bin/entrypoint-dind.sh

WORKDIR /workspace
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint-dind.sh"]
CMD ["/bin/zsh"]
