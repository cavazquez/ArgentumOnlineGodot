# Distribuciones coordinadas

Servidor y cliente usan una única versión de producto. No se mantiene
compatibilidad con clientes anteriores durante la etapa previa a producción.
Cada entrega registra ambos commits, motor fijado, arquitectura, hashes y pruebas.

`export-portable.py export` genera candidatos Windows x86_64, Linux x86_64,
Linux ARM64, macOS y web. Linux admite reutilizar su export nativo para evitar
compilar dos veces los mismos recursos. No se requiere instalar Godot para usar
un portable. El archivo LICENSE y las instrucciones viajan con cada paquete.

`smoke-portable.py` copia el candidato fuera del checkout a una carpeta con
espacios y ejecuta esos mismos bytes. Prueba dos clientes, login TLS real contra
el servidor de la misma versión, recursos completos, movimiento, inventario,
audio, teclado, preferencias y reconexión con Redis 8.10.2 aislado. El controlador
de aceptación cambia sólo la escena de entrada durante la prueba, nunca el
ejecutable del candidato. Los dispositivos y el driver de audio constan en los
recibos; la prueba de reproducción no acredita audibilidad en un altavoz físico.

Windows se verifica en Windows Server 2025; sólo Redis de la fixture corre en
WSL. No se distribuye un servidor Redis para Windows. macOS se verifica en un
runner macOS nativo; el bundle usa firma ad hoc y no está notarizado. La carpeta
de preferencias usa las ubicaciones de usuario de Godot de cada sistema.

Web se verifica en Chromium con HTTPS, el endpoint WSS binario y almacenamiento
separado por servidor. La prueba recarga páginas, cambia de servidor, verifica
ausencia de secretos y simula almacenamiento bloqueado. La excepción de confianza
del navegador se limita a la huella SPKI del certificado efímero de la fixture.

`export-portable.py seal` exige prueba de la plataforma, commit y manifiesto
exactos antes de crear el ZIP verificado. Todos los archivos se vuelven a hashear.
Ningún job de compilación publica automáticamente en GitHub ni en la Store.
Los Snaps ARM64 requieren runner ARM64, instalación estricta y prueba funcional
previa a cualquier promoción. Una prueba fallida conserva el issue abierto.
