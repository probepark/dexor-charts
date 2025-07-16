#!/bin/bash
set -euo pipefail

BUCKET_NAME="${bucket_name}"
URL_MAP_NAME="${url_map_name}"
ENVIRONMENT="${environment}"
CACHE_INVALIDATION_ENABLED="${cache_invalidation_enabled}"

echo "Deploying frontend to $ENVIRONMENT environment..."

# Set cache control headers based on file type
echo "Setting cache control headers..."
gsutil -m setmeta -h "Cache-Control:public, max-age=31536000, immutable" "gs://$BUCKET_NAME/static/**/*"
gsutil -m setmeta -h "Cache-Control:public, max-age=3600" "gs://$BUCKET_NAME/*.html"
gsutil -m setmeta -h "Cache-Control:public, max-age=3600" "gs://$BUCKET_NAME/*.json"
gsutil -m setmeta -h "Cache-Control:public, max-age=86400" "gs://$BUCKET_NAME/assets/**/*"

# Set content types
echo "Setting content types..."
gsutil -m setmeta -h "Content-Type:text/html; charset=utf-8" "gs://$BUCKET_NAME/**/*.html"
gsutil -m setmeta -h "Content-Type:application/javascript; charset=utf-8" "gs://$BUCKET_NAME/**/*.js"
gsutil -m setmeta -h "Content-Type:text/css; charset=utf-8" "gs://$BUCKET_NAME/**/*.css"
gsutil -m setmeta -h "Content-Type:application/json; charset=utf-8" "gs://$BUCKET_NAME/**/*.json"
gsutil -m setmeta -h "Content-Type:image/svg+xml" "gs://$BUCKET_NAME/**/*.svg"

# Set compression
echo "Enabling compression for text files..."
gsutil -m setmeta -h "Content-Encoding:gzip" "gs://$BUCKET_NAME/**/*.js"
gsutil -m setmeta -h "Content-Encoding:gzip" "gs://$BUCKET_NAME/**/*.css"
gsutil -m setmeta -h "Content-Encoding:gzip" "gs://$BUCKET_NAME/**/*.html"
gsutil -m setmeta -h "Content-Encoding:gzip" "gs://$BUCKET_NAME/**/*.json"

# Invalidate CDN cache if enabled
if [ "$CACHE_INVALIDATION_ENABLED" = "true" ]; then
    echo "Invalidating CDN cache..."
    gcloud compute url-maps invalidate-cdn-cache "$URL_MAP_NAME" \
        --path "/*" \
        --async
    echo "CDN cache invalidation initiated (running asynchronously)"
fi

echo "Deployment completed successfully!"