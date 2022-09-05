#!/bin/bash
POST_NAME=$(echo -n $@|sed 's/[^[:alnum:]]\+//g')
DATE=$(date -I)
TEMP_NAME="$DATE-$POST_NAME.md"
echo touch "_posts/$TEMP_NAME"
