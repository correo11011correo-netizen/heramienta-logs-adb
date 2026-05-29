#!/bin/bash

# Function to display error messages and exit
error_exit() {
  echo "❌ Error: $1" >&2
  exit 1
}

# Function to clean up resources (stop logging, force stop app)
cleanup() {
  echo ""
  echo "🛑 Deteniendo la captura de logs..."
  # Kill the background logcat process if it's running
  if [ -n "$LOGCAT_PID" ] && ps -p $LOGCAT_PID > /dev/null; then
    kill "$LOGCAT_PID" 2>/dev/null
  fi
  echo "🛑 Forzando detenci\303\263n de la app: $PACKAGE_NAME..."
  adb shell am force-stop "$PACKAGE_NAME" > /dev/null 2>&1
  echo "Limpieza completada."
  exit 0
}

# Trap SIGINT (Ctrl+C) to call cleanup function
trap cleanup SIGINT

# Check if a package name was provided as an argument
if [ -n "$1" ]; then
  PACKAGE_NAME="$1"
  echo "📦 Paquete proporcionado: $PACKAGE_NAME"
else
  echo "📱 Buscando aplicaciones instaladas..."
  # Get a list of packages, sort them, and present with numbers
  # Use 'pm list packages -f' to get package path, then extract package name
  PACKAGES_INFO=$(adb shell pm list packages -f | sort)
  PACKAGE_NAMES=()

  # Parse the output to get package names and store them
  while IFS= read -r line; do
    # Extract package name from "package:/path/to/app.apk=package.name"
    PACKAGE_NAME_LOOP=$(echo "$line" | awk -F'=' '{print $NF}')
    if [ -n "$PACKAGE_NAME_LOOP" ]; then
      PACKAGE_NAMES+=("$PACKAGE_NAME_LOOP")
    fi
  done < <(echo "$PACKAGES_INFO")

  if [ ${#PACKAGE_NAMES[@]} -eq 0 ]; then
    error_exit "No se encontraron aplicaciones instaladas."
  fi

  echo "Selecciona la aplicación de la que deseas capturar logs:"
  for i in "${!PACKAGE_NAMES[@]}"; do
    printf "%3d) %s
" "$((i+1))" "${PACKAGE_NAMES[$i]}"
  done

  echo ""
  read -rp "👉 Ingresa el número de la app (o presiona Enter para salir): " CHOICE

  if [[ -z "$CHOICE" ]]; then
    echo "Operación cancelada por el usuario."
    exit 0
  fi

  # Validate choice
  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#PACKAGE_NAMES[@]}" ]; then
    error_exit "Selección inválida. Por favor, ingresa un número de la lista."
  fi

  PACKAGE_NAME="${PACKAGE_NAMES[$((CHOICE-1))]}"
  echo "App seleccionada: $PACKAGE_NAME"
fi

# Resolve the main activity for the selected package
echo "🔎 Resolviendo la actividad principal para $PACKAGE_NAME..."
# Use 'cmd package resolve-activity --brief' to get the main launchable activity.
ACTIVITY_INFO=$(adb shell cmd package resolve-activity --brief "$PACKAGE_NAME" 2>&1)
MAIN_ACTIVITY=$(echo "$ACTIVITY_INFO" | grep "$PACKAGE_NAME" | head -n 1)

if [ -z "$MAIN_ACTIVITY" ]; then
  # Fallback or error if resolve-activity fails
  error_exit "No se pudo resolver la actividad principal para '$PACKAGE_NAME'. Asegúrate de que la app esté instalada y sea ejecutable. Detalles del error: $ACTIVITY_INFO"
fi
echo "Actividad principal detectada: $MAIN_ACTIVITY"

# Launch the app
echo "🚀 Lanzando la aplicación: $PACKAGE_NAME..."
adb shell am start -n "$MAIN_ACTIVITY" || error_exit "No se pudo lanzar la aplicación '$PACKAGE_NAME' con actividad '$MAIN_ACTIVITY'. Verifica que la ruta sea correcta."
echo "Aplicación lanzada. Esperando un momento para que inicie..."
sleep 3 # Give the app a moment to start and generate initial logs

# Clear previous logs
echo "🧹 Limpiando logs previos..."
adb logcat -c

# Start capturing logs for the selected package
echo "📡 Capturando logs para '$PACKAGE_NAME' (actividad: $MAIN_ACTIVITY)..."
echo "Presiona CTRL+C para detener la captura."

# Run adb logcat in the background and store its PID
# Use --line-buffered for grep to ensure logs are output immediately
adb logcat | grep --line-buffered "$PACKAGE_NAME" & 
LOGCAT_PID=$!

# Wait for the logcat process to finish (e.g., by Ctrl+C)
# The `wait` command will block until the background process ($LOGCAT_PID) terminates.
# When SIGINT is received, `trap cleanup SIGINT` will execute `cleanup`, which kills $LOGCAT_PID,
# causing `wait $LOGCAT_PID` to unblock.
wait $LOGCAT_PID

# The trap will handle the exit after wait unblocks
