#!/bin/bash
#
# Build (and optionally push) the Focalboard multi-arch Docker image.
# Adapted from the rustfs docker-buildx.sh packaging pattern.
#
# Usage:
#   ./docker-buildx.sh -r registry.cn-hangzhou.aliyuncs.com -n <your-namespace> --push
#
# Prerequisites:
#   - Docker with buildx support (docker buildx version)
#   - Already logged in to the target registry (docker login <registry>)
#
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
REGISTRY="registry.cn-hangzhou.aliyuncs.com"
NAMESPACE="focalboard"
PLATFORMS="linux/amd64,linux/arm64"
PUSH=false
NO_CACHE=false

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --registry REGISTRY    Docker registry (default: registry.cn-hangzhou.aliyuncs.com)"
    echo "  -n, --namespace NAMESPACE  Image namespace (default: focalboard)"
    echo "  -p, --platforms PLATFORMS  Target platforms (default: linux/amd64,linux/arm64)"
    echo "  --push                     Push images to registry"
    echo "  --no-cache                 Disable build cache"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Build locally only"
    echo "  $0 --push                                       # Build and push to default registry"
    echo "  $0 -r registry.cn-hangzhou.aliyuncs.com -n myns --push   # Push to ACR"
}

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

check_buildx() {
    if ! docker buildx version >/dev/null 2>&1; then
        print_message $RED "❌ Docker buildx is not available. Please install Docker with buildx support."
        exit 1
    fi
}

setup_builder() {
    local builder_name="focalboard-builder"

    print_message $BLUE "🔧 Setting up Docker buildx builder..."

    if docker buildx ls | grep -q "$builder_name"; then
        print_message $YELLOW "⚠️  Builder '$builder_name' already exists, using existing one"
        docker buildx use "$builder_name"
    else
        docker buildx create --name "$builder_name" --driver docker-container --bootstrap
        docker buildx use "$builder_name"
        print_message $GREEN "✅ Created and activated builder '$builder_name'"
    fi

    docker buildx inspect --bootstrap
}

get_version() {
    # Prefer a git tag; fall back to short commit hash.
    if git describe --abbrev=0 --tags >/dev/null 2>&1; then
        git describe --abbrev=0 --tags
    else
        git rev-parse --short HEAD
    fi
}

build_and_push() {
    local version=$(get_version)
    local image_base="${REGISTRY}/${NAMESPACE}/focalboard"
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local vcs_ref=$(git rev-parse --short HEAD)

    print_message $BLUE "🚀 Building Focalboard Docker image..."
    print_message $YELLOW "   Version:   $version"
    print_message $YELLOW "   Registry:  $REGISTRY"
    print_message $YELLOW "   Namespace: $NAMESPACE"
    print_message $YELLOW "   Platforms: $PLATFORMS"
    print_message $YELLOW "   Build Date: $build_date"
    print_message $YELLOW "   VCS Ref:   $vcs_ref"
    print_message $YELLOW "   Push:      $PUSH"
    print_message $YELLOW "   No Cache:  $NO_CACHE"
    echo ""

    local build_cmd="docker buildx build"
    build_cmd+=" --platform $PLATFORMS"
    build_cmd+=" --build-arg BUILD_DATE=$build_date"
    build_cmd+=" --build-arg VCS_REF=$vcs_ref"

    if [ "$NO_CACHE" = true ]; then
        build_cmd+=" --no-cache"
    fi

    if [ "$PUSH" = true ]; then
        build_cmd+=" --push"
    else
        build_cmd+=" --load"
    fi

    # Tag with the version (git tag or short hash) and "latest".
    build_cmd+=" -t ${image_base}:${version}"
    build_cmd+=" -t ${image_base}:latest"
    build_cmd+=" -f Dockerfile.buildx ."

    print_message $BLUE "📦 Executing: $build_cmd"
    if eval $build_cmd; then
        print_message $GREEN "✅ Successfully built ${image_base}:${version} and :latest"
    else
        print_message $RED "❌ Failed to build Focalboard image"
        exit 1
    fi

    docker buildx prune -f
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -p|--platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_message $RED "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

check_buildx
setup_builder
build_and_push
