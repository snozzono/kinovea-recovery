# recuperar-kinovea

Script de PowerShell para buscar y recuperar archivos de Kinovea (videos y .kva) en Windows.

Busca en:
- Papelera de reciclaje
- Copias de sombra (Versiones anteriores), requiere ejecutar como administrador
- Historial de archivos
- Carpetas del usuario y las rutas que aparecen en la configuracion de Kinovea (`%APPDATA%\Kinovea`)

Las fuentes no se modifican. Lo encontrado se copia a una carpeta del Escritorio con un `manifiesto.csv`.

## Uso

Descargar y ejecutar (PowerShell):

```powershell
curl.exe -o recuperar-kinovea.ps1 https://raw.githubusercontent.com/snozzono/kinovea-recovery/main/recuperar-kinovea.ps1
powershell -ExecutionPolicy Bypass -File .\recuperar-kinovea.ps1 -Filtro partido
```

- `-Filtro` es parte del nombre del archivo (sin extension). Sin el parametro busca todo.
- `-Destino` permite elegir otra carpeta de salida.
- Para copias de sombra, abrir PowerShell como administrador.
