#!/bin/bash

echo "==> Pull additional container images"

source ./config.sh
source scripts/common.sh
source scripts/images.sh

#cat imagelists/*.txt | sed "s/#.*$//g" | sort -u > $IMAGES_DIR/additional-images.list
#빈문자열 제거등 강력 제거
cat imagelists/*.txt | sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' -e '/^#/d' | sort -u > $IMAGES_DIR/additional-images.list
cat $IMAGES_DIR/additional-images.list

IMAGES=$(cat $IMAGES_DIR/additional-images.list)

for image in $IMAGES; do
    image=$(expand_image_repo $image)
    get_image $image
done

