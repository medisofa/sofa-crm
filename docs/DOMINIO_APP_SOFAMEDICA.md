# Dominio personalizado SOFA

Dominio objetivo:

```
app.sofamedica.com
```

El archivo `CNAME` en la raíz del repositorio contiene exactamente:

```
app.sofamedica.com
```

## Configuración DNS requerida

Crear en el proveedor DNS de `sofamedica.com`:

- Tipo: `CNAME`
- Nombre/Host: `app`
- Destino: `medisofa.github.io`

## Configuración en GitHub Pages

En el repositorio:

```
Settings → Pages → Custom domain
```

usar:

```
app.sofamedica.com
```

Después de validar el dominio, activar:

```
Enforce HTTPS
```

## Configuración de Supabase Auth

Agregar temporalmente ambas URLs permitidas durante la transición:

```
https://app.sofamedica.com/**
https://medisofa.github.io/sofa-crm/**
```

y establecer como Site URL cuando se haga el cambio controlado:

```
https://app.sofamedica.com
```

No eliminar la URL de GitHub Pages hasta validar login, logout y redirecciones.
