# GitHub Workflows Configuration

Este documento describe los flujos de trabajo configurados para el Firebird Adapter.

## 🔄 Workflows Configurados

### 1. **CI - Firebird Adapter** (`.github/workflows/ci.yml`)
- **Disparador**: Push y Pull Request a `master`, `main`, `rails-7-2`
- **Propósito**: Validaciones rápidas y básicas
- **Acciones**:
  - ✅ Sintaxis de archivos Ruby
  - ✅ Validación de carga del adaptador
  - ✅ Tests rápidos sin base de datos
  - ✅ Verificación de dependencias
  - ✅ Intento de ejecutar RSpec

### 2. **Full Test Suite** (`.github/workflows/main.yml`)
- **Disparador**: Push y Pull Request a `master`, `main`, `rails-7-2`
- **Propósito**: Ejecutar suite completa de tests
- **Acciones**:
  - 🐳 Contenedor Docker con Firebird 5.0
  - 🧪 Ejecución de tests con `bundle exec rake`
  - 📋 Ejecución de specs con `bundle exec rspec`
  - 🔍 Linting con RuboCop
  - 💎 Validación de construcción del gem
  - 🔌 Validación de carga del adaptador

### 3. **Quality Checks** (`.github/workflows quality.yml`)
- **Disparador**: Push y Pull Request
- **Propósito**: Análisis de calidad y seguridad
- **Acciones**:
  - 🔍 Linting con RuboCop (formato GitHub)
  - 🔒 Auditoría de seguridad con bundler-audit
  - 📦 Verificación de dependencias
  - 💎 Validación de gemspec
  - 🏗️ Construcción del gem
  - 📊 Verificación de tamaño del gem
  - 📚 Validación de documentación

### 4. **Release Checks** (`.github/workflows/release.yml`)
- **Disparador**: Tags (`v*`) y cambios en version/gemspec
- **Propósito**: Validaciones previas a release
- **Acciones**:
  - 🏷️ Validación de versiones (archivo vs gemspec vs tag)
  - 🏗️ Construcción del gem
  - 🔍 Validación del gem construido
  - 📦 Verificación de contenidos del gem
  - 🧪 Ejecución de tests previos al release
  - 📅 Verificación de changelog
  - 🚀 Publicación a RubyGems (solo en tags)
  - 📝 Creación de GitHub Release (solo en tags)

### 5. **Test Results** (`.github/workflows/test-results.yml`)
- **Disparador**: Completación del workflow "Full Test Suite"
- **Propósito**: Reporte de resultados
- **Acciones**:
  - 📊 Reporte de estado de tests
  - 📈 Análisis de cobertura (exitoso)
  - 🔗 Enlaces a resultados detallados

### 6. **Dependency & Security** (`.github/workflows/security.yml`)
- **Disparador**: Schedule (lunes 9AM UTC) y cambios en dependencias
- **Propósito**: Auditorías de seguridad y dependencias
- **Acciones**:
  - 🔒 Auditoría de seguridad con bundler-audit
  - 📦 Verificación de dependencias desactualizadas
  - 📋 Generación de reporte de seguridad
  - 🔍 Revisión de dependencias en PRs

## 🎯 Cobertura

### Ramas Monitoreadas:
- ✅ `master` (rama principal)
- ✅ `main` (compatibilidad)
- ✅ `rails-7-2` (desarrollo)

### Eventos Monitoreados:
- ✅ Push a cualquier rama monitoreada
- ✅ Pull Requests a cualquier rama monitoreada
- ✅ Creación de tags (`v*`)
- ✅ Schedule (seguridad semanal)

### Validaciones Ejecutadas:
- ✅ **Sintaxis**: Todos los archivos Ruby
- ✅ **Carga**: El adaptador se carga correctamente
- ✅ **Tests**: Suite completa con RSpec
- ✅ **Linting**: RuboCop con formato GitHub
- ✅ **Seguridad**: bundler-audit
- ✅ **Construcción**: Gem se construye sin errores
- ✅ **Versiones**: Coherencia entre archivos
- ✅ **Documentación**: README y archivos existentes

## 🔧 Variables de Entorno

Las workflows usan estas variables:
- `DATABASE_URL`: Para conexión a Firebird
- `DB_HOST`: Host de base de datos
- `FIREBIRD_INCLUDE`: Headers de Firebird
- `FIREBIRD_LIB`: Librerías de Firebird
- `GITHUB_TOKEN`: Para crear releases
- `RUBYGEMS_AUTH_TOKEN`: Para publicar gems

## 🚀 Publicación Automática

Cuando se crea un tag `v*`:
1. **Validación**: Se ejecutan todas las validaciones
2. **Construcción**: Se construye el gem
3. **Publicación**: Se publica a RubyGems
4. **Release**: Se crea un GitHub Release

## 📈 Reportes

- **GitHub Actions**: Resultados en tiempo real
- **GitHub Issues**: Errores de seguridad
- **GitHub Releases**: Versiones publicadas
- **Pull Requests**: Revisiones de dependencias

## 🔄 Mejoras Recientes

1. **Cobertura múltiple**: Todas las ramas principales
2. **Validación robusta**: Múltiples capas de verificación  
3. **Publicación automática**: Streamlineado para releases
4. **Seguridad proactiva**: Auditorías regulares
5. **Reportes integrales**: Visibilidad completa

---

**Nota**: Estos workflows aseguran calidad, seguridad y consistencia en cada cambio y release del Firebird Adapter.