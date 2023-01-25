#!/bin/bash
POST_NAME=$(echo -n $@|sed 's/[^[:alnum:]]\+//g')
DATE=$(date -I)
TEMP_NAME="$DATE-$POST_NAME.md"
touch "_posts/$TEMP_NAME"
echo '---
title: Title
articles:
   excerpt_type: html
---
' > "_posts/$TEMP_NAME"
vim "_posts/$TEMP_NAME"
