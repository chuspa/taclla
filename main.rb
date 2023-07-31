require 'json'
require 'fileutils'
require './Utils'
require 'pathname'
require 'shellwords'

def readPrototypeKey(file, keyName)
  link = Shellwords.escape(file)
  %x{defaults read #{link} #{keyName}}.chomp
end

def parseAppInfo(appBaseLocate, appInfoFile)
  appInfo = {}
  appInfo['appBaseLocate'] = "#{appBaseLocate}"
  appInfo['CFBundleIdentifier'] = readPrototypeKey appInfoFile, 'CFBundleIdentifier'
  appInfo['CFBundleVersion'] = readPrototypeKey appInfoFile, 'CFBundleVersion'
  appInfo['CFBundleShortVersionString'] = readPrototypeKey appInfoFile, 'CFBundleShortVersionString'
  appInfo['CFBundleName'] = readPrototypeKey appInfoFile, 'CFBundleExecutable'
  appInfo
end

def scan_apps
  applist = []
  baseDir = '/Applications'
  lst = Dir.glob("#{baseDir}/*")
  lst.each do |app|
    appInfoFile = "#{app}/Contents/Info.plist"
    next unless File.exist?(appInfoFile)
    begin
      applist.push parseAppInfo app, appInfoFile
      # puts "检查本地App: #{appInfoFile}"
    rescue StandardError
      next
    end
  end
  applist
end

def checkCompatible(compatibleVersionCode, compatibleVersionSubCode, appVersionCode, appSubVersionCode)
  return true if compatibleVersionCode.nil? && compatibleVersionSubCode.nil?
  compatibleVersionCode&.each do |code|
    return true if appVersionCode == code
  end

  compatibleVersionSubCode&.each do |code|
    return true if appSubVersionCode == code
  end
  false
end

def main

  puts "Preparando los ajustes de entorno..."

  ret = %x{csrutil status}.chomp
  # System Integrity Protection status: disabled.
  if ret.include?("status: enabled")
    puts "¡Desactiva tu SIP para instalar! ¿Es necesario desactivar SIP? \nEstá escrito en los requisitos desactivar el SIP primero, ¿puedes leer las instrucciones que escribí? \nSi lo leíste y aún no lo desactivas, significa que realmente eres un idiota\nSi no leíste las instrucciones, entonces eres aún más idiota."
    return
  end

  puts "====\tEl script autoinyectado comienza a ejecutarse ====\n"
  puts "\tDesign By QiuChenly ... Sensei"
  puts "Al inyectar, ingrese 'y' de acuerdo con el mensaje \n o presione Entrar para omitir este elemento.\n"

  install_apps = scan_apps

  config = File.read("config.json")
  config = JSON.parse config
  basePublicConfig = config['basePublicConfig']
  appList = config['AppList']
   #preparar la lista de paquetes de resolución
  appLst = []
  appList.each do |app|
    packageName = app['packageName']
    if packageName.is_a?(Array)
      packageName.each { |name|
        tmp = app.dup
        tmp['packageName'] = name
        appLst.push tmp
      }
    else
      appLst.push app
    end
  end

  appLst.each { |app|
    packageName = app['packageName']
    appBaseLocate = app['appBaseLocate']
    bridgeFile = app['bridgeFile']
    injectFile = app['injectFile']
    supportVersion = app['supportVersion']
    supportSubVersion = app['supportSubVersion']
    extraShell = app['extraShell']
    # puts "Nombre del paquete leído localmente #{packageName}"

    localApp = install_apps.select { |_app| _app['CFBundleIdentifier'] == packageName }
    if localApp.empty? && (appBaseLocate.nil? || !Dir.exist?(appBaseLocate))
      next
    end

    if localApp.empty?
      puts "[🔔] Este paquete de App no esta en el lugar correcto\n, tenga en cuenta que la ruta de inyección de la aplicación actual es #{appBaseLocate}"
      puts "leido por #{appBaseLocate + "/Contents/Info.plist"}"      # puts "读取的是 #{appBaseLocate + "/Contents/Info.plist"}"
      localApp.push(parseAppInfo appBaseLocate, appBaseLocate + "/Contents/Info.plist")
    end

    localApp = localApp[0]
    if appBaseLocate.nil?
      appBaseLocate = localApp['appBaseLocate']
    end
    bridgeFile = basePublicConfig['bridgeFile'] if bridgeFile.nil?

    unless checkCompatible(supportVersion, supportSubVersion, localApp['CFBundleShortVersionString'], localApp['CFBundleVersion'])
      puts "[😅] [#{localApp['CFBundleName']}] - [#{localApp['CFBundleShortVersionString']}] - [#{localApp['CFBundleIdentifier']}] No es una versión compatible, omita la inyección😋。\n"
      next
    end

    puts "[🤔] [#{localApp['CFBundleName']}] - [#{localApp['CFBundleShortVersionString']}] - [#{localApp['CFBundleIdentifier']}]es una versión compatible, ¿necesita inyectar？y/n (por defecto n)\n"
    action = gets.chomp
    next if action != 'y'
    puts "Iniciando la inyecccion de la aplicación: #{packageName}"

    dest = appBaseLocate + bridgeFile + injectFile
    backup = dest + "_backup"

    if File.exist? backup
      puts "El archivo de inyección de respaldo ya existe, ¿necesito usar este archivo para inyectar directamente? y/n (predeterminado y)\n"
      action = gets.chomp
      # action = 'y'
      if action == 'n'
        FileUtils.remove(backup)
        FileUtils.copy(dest, backup)
      else

      end
    else
      FileUtils.copy(dest, backup)
    end

    current = Pathname.new(File.dirname(__FILE__)).realpath
    current = Shellwords.escape(current)
    # set shell +x permission
    sh = "chmod +x #{current}/tool/insert_dylib"
    # puts sh
    system sh
    backup = Shellwords.escape(backup)
    dest = Shellwords.escape(dest)
    sh = "sudo #{current}/tool/insert_dylib #{current}/tool/libInjectLib.dylib #{backup} #{dest}"
    # puts sh
    system sh
    sh = "codesign -f -s - --timestamp=none --all-architectures #{dest}"
    system sh
    sh = "sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true"
    system sh

    unless extraShell.nil?
      # los extrashell deben estar en cada app
      system "sudo sh #{current}/appstore/" + extraShell
    end
  }
end

main