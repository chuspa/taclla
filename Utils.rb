# frozen_string_literal: true

# Comprobar si el archivo existe
# Parámetros.
# file_path: ruta del archivo
# Valor de retorno.
# yes existe o no
def file_exist?(file_path)
  File.exist?(file_path)
end

