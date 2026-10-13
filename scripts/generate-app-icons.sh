#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
source_directory="$repository_root/AppLauncher/Resources/AppIconSource/Floating"
asset_directory="$repository_root/AppLauncher/Resources/Assets.xcassets/AppIcon.appiconset"

# The Paper exports are the artwork authority. Resample them without adding effects.
for appearance in Light Dark; do
  source_png="$source_directory/Floating-$appearance.png"
  if [[ ! -f "$source_png" ]]; then
    print -u2 "Missing Paper master export: $source_png"
    exit 1
  fi
  iconset="$source_directory/$appearance.iconset"
  mkdir -p "$iconset"
  for point_size in 16 32 128 256 512; do
    for scale in 1 2; do
      suffix=""
      if (( scale == 2 )); then suffix="@2x"; fi
      pixels=$(( point_size * scale ))
      filename="icon_${point_size}x${point_size}${suffix}.png"
      sips --resampleHeightWidth "$pixels" "$pixels" "$source_png" \
        --out "$iconset/$filename" >/dev/null
    done
  done
  iconutil --convert icns "$iconset" --output "$source_directory/Floating-$appearance.icns"
done

# Composer supplies its own mask and outer margin. Normalize only its internal
# inputs to the Paper plate bounds (x=39, y=35, width=434, height=436 in 512 units).
# Keep the original exports and legacy iconset geometry unchanged.
composer_assets="$repository_root/AppLauncher/Resources/AppIcon.icon/Assets"
if [[ -d "$composer_assets" ]]; then
  for appearance in Light Dark; do
    source_png="$source_directory/Floating-$appearance.png"
    destination_png="$composer_assets/Floating-$appearance.png"
    sips --cropToHeightWidth 872 868 --cropOffset 70 78 "$source_png" \
      --out "$destination_png" >/dev/null
    sips --resampleHeightWidth 1024 1024 "$destination_png" >/dev/null
  done
fi

# Default legacy artwork. The Icon Composer document supplies system appearances.
mkdir -p "$asset_directory"
cp "$source_directory/Light.iconset/"*.png "$asset_directory/"
cp "$source_directory/Floating-Light.icns" "$repository_root/AppLauncher/Resources/AppIcon.icns"
print "Generated 20 macOS icon PNGs and both ICNS files from Paper's Floating masters."
