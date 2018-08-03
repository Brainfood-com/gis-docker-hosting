#!/bin/bash

set -e


parse_manifest() {
	gawk '
function url_quote(text) {
	text = gensub(/%/, "%25", "g", text)
	text = gensub(/:/, "%3A", "g", text)
	return text
}

/"service": {/,/}$/{
	q=gensub(/.*"@id": "(.*)",?/, "\\1", "g")
	if (q != $0 && q !~ /_thumb$/) {
		print q, url_quote(q)
	}
}' "$1"
}

ensure_url_safely() {
	declare url="$1" dir="$2" file="$3"
	if ! [[ -e "$dir/$file" ]]; then
		echo "Fetching $url"
		wget -q -O "$dir/.tmp.$file" "$url"
		mv "$dir/.tmp.$file" "$dir/$file"
	fi
}

download_image_grid() {
	declare iiif_id="$1" iiif_dir="$2"
	declare target_dir="data/mirror/$iiif_dir"
	mkdir -p "$target_dir"
	ensure_url_safely "$iiif_id/info.json" "data/mirror/$iiif_dir" "info.json"
	declare format IFS
	declare -i tile_width width height
	read format tile_width width height < <(echo $(jq '.profile[1].formats[0], .tiles[0].width, .width,.height' "data/mirror/$iiif_dir/info.json"))
	[[ $format =~ ^'"'(.*)'"'$ ]] && format="${BASH_REMATCH[1]}"

	if ! [[ -e "$target_dir/full.$format" ]]; then
		declare -i x=0 y=0 x_width y_width
		declare -a image_cells image_files
		declare image_file
		declare -i x_count=$((($width + $tile_width - 1) / $tile_width))
		declare -i y_count=$((($height + $tile_width - 1) / $tile_width))

		for ((y=0; y < $height; y=$(($y + $tile_width)) )); do
			if [[ $(($y + $tile_width)) -gt $height ]]; then
				y_width=$(($height - $y))
			else
				y_width=$tile_width
			fi
			for ((x=0; $x < $width; x=$(($x + $tile_width)) )); do
				if [[ $(($x + $tile_width)) -gt $width ]]; then
					x_width=$(($width - $x))
				else
					x_width=$tile_width
				fi
				image_file="$x,$y,$tile_width,$tile_width/$x_width,$y_width/0/default.$format"
				if ! [[ -e $target_dir/$image_file ]]; then
					image_cells+=("$iiif_id/$x,$y,$tile_width,$tile_width/$x_width,$y_width/0/default.$format")
				fi
				image_files+=("$image_file")
			done
		done
		declare parts
		IFS="/" parts=($iiif_id)
		#declare -p parts
		echo "${image_cells[@]}" | tr ' ' '\n' | xargs -r -n 10 -P 3 wget -nH -np --cut-dirs="$((${#parts[*]} - 3))" -P "$target_dir" -m -np
		if false; then
			(
				cd "$target_dir"
				montage "${image_files[@]}" -mode concatenate -tile "${x_count}x${y_count}" "tmp.full.$format"
				mv "tmp.full.$format" "full.$format"
			)
		fi
	fi
}

set -x
declare -a manifest_files=( $(find data/media.getty.edu -name 'manifest.json') )
for manifest_file in "${manifest_files[@]}"; do
	echo "Manifest: $manifest_file"
	while read iiif_id iiif_dir; do
		download_image_grid "$iiif_id" "$iiif_dir"
	done < <(parse_manifest "$manifest_file")
done
