import os
import subprocess
import zipfile

base_dir = r"c:\Robo Virada de Delta\Valid_BOS_Pullback\Bookmap_Addon"
src_file = os.path.join(base_dir, r"src\com\viniciusburgo\bridge\BookmapMT5Bridge.java")
classes_dir = os.path.join(base_dir, "classes")
os.makedirs(classes_dir, exist_ok=True)

cp = r"C:\Program Files\Bookmap\lib\bm-simplified-api-wrapper.jar;C:\Program Files\Bookmap\lib\bm-l1api.jar"
cmd = [
    r"C:\Program Files\Bookmap\jre\bin\java.exe",
    "-jar", r"c:\Robo Virada de Delta\Valid_BOS_Pullback\ecj.jar",
    "-cp", cp,
    "-1.8",
    "-d", classes_dir,
    src_file
]

print("Compilando Java...")
res = subprocess.run(cmd, capture_output=True, text=True)
print("Return code:", res.returncode)
if res.stdout:
    print("Stdout:", res.stdout)
if res.stderr:
    print("Stderr:", res.stderr)

if res.returncode == 0:
    jar_path = os.path.join(base_dir, "BookmapMT5Bridge.jar")
    print(f"Empacotando JAR em: {jar_path}")
    with zipfile.ZipFile(jar_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        # Add Manifest
        manifest = "Manifest-Version: 1.0\nCreated-By: @viniciusburgo\n"
        z.writestr("META-INF/MANIFEST.MF", manifest)
        
        # Add app.properties for Bookmap
        app_prop = "version=1.0\nminBookmapVersion=7.3.0.1\n"
        z.writestr("app.properties", app_prop)
        
        # Add class files
        for root, dirs, files in os.walk(classes_dir):
            for f in files:
                full_p = os.path.join(root, f)
                rel_p = os.path.relpath(full_p, classes_dir)
                z.write(full_p, rel_p)
                print("  Adicionado:", rel_p)
                
    print(f"\n[SUCESSO] Addon compilado: {jar_path} ({os.path.getsize(jar_path)} bytes)")
else:
    print("[ERRO] Falha na compilação do Addon.")
