# Dockerfile para desarrollo de gemas
FROM ruby:3.3.6

# Usar mirror más estable y configurar retry
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    pkg-config \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Instalar dependencias de Firebird con retry
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    firebird-dev \
    firebird-utils \
    libfbclient2 || \
    (echo "Retrying Firebird installation..." && \
     apt-get update -qq && \
     apt-get install --no-install-recommends -y \
     firebird-dev \
     firebird-utils \
     libfbclient2) && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

# Copiar Gemfile primero
COPY Gemfile* ./

# Copiar todo el código (el orden importa para el cache de Docker)
COPY . .

# Instalar dependencias
RUN bundle install

# Comando por defecto - mantener el contenedor corriendo
CMD ["tail", "-f", "/dev/null"]
