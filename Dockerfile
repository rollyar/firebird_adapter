# Dockerfile para desarrollo de gemas
FROM ruby:3.3.6-slim

# Instalar dependencias del sistema
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    pkg-config \
    firebird-dev \
    firebird-utils \
    libfbclient2 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /app

# Copiar archivos de la gema
COPY . .

# Instalar dependencias
RUN bundle install

# Comando por defecto - mantener el contenedor corriendo
CMD ["tail", "-f", "/dev/null"]
