#!/bin/bash

# SK-ChimeraOS Sync Script
# 用于同步 3003n/chimeraos 仓库的 release 信息和 checksum 文件

set -euo pipefail

# 脚本参数
TRIGGER_TYPE="${1:-schedule}"
SPECIFIC_TAG="${2:-}"
FORCE_RESYNC="${3:-false}"
MAX_RELEASES="${4:-10}"

# 参数验证
if ! [[ "$MAX_RELEASES" =~ ^[0-9]+$ ]]; then
  echo "❌ MAX_RELEASES 必须是数字: $MAX_RELEASES"
  exit 1
fi

# 常量配置
readonly CHIMERAOS_REPO="3003n/chimeraos"
readonly API_BASE_URL="https://api.github.com"
readonly RELEASES_API_URL="${API_BASE_URL}/repos/${CHIMERAOS_REPO}/releases"
readonly TARGET_DIR="sk-chimeraos"
readonly CHECKSUM_DIR="${TARGET_DIR}/checksum"
readonly RELEASE_JSON="${TARGET_DIR}/release.json"

# 颜色输出
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 日志函数
log_info() {
  echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}" >&2
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

log_error() {
  echo -e "${RED}❌ $1${NC}" >&2
}

# 格式化文件大小
format_size() {
  local size="$1"
  if [[ $size -gt 1048576 ]]; then
      echo "$(($size / 1048576))MB"
  elif [[ $size -gt 1024 ]]; then
      echo "$(($size / 1024))KB"
  else
      echo "${size}B"
  fi
}

# 获取 GitHub API 数据
get_releases_data() {
  log_info "正在获取 ChimeraOS releases 信息..."
  
  local api_response
  if ! api_response=$(curl -s \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${RELEASES_API_URL}?per_page=100" 2>/dev/null); then
      log_error "API 请求失败"
      return 1
  fi
  
  # 验证 API 响应
  if ! echo "$api_response" | jq empty 2>/dev/null; then
      log_error "API 返回的不是有效的 JSON"
      log_error "响应内容前100字符: ${api_response:0:100}..."
      return 1
  fi
  
  # 检查是否是错误响应
  if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
      local error_msg
      error_msg=$(echo "$api_response" | jq -r '.message')
      log_error "GitHub API 错误: $error_msg"
      return 1
  fi
  
  local count
  count=$(echo "$api_response" | jq '. | length' 2>/dev/null || echo "0")
  log_success "成功获取到 $count 个 releases"
  echo "$api_response"
}

# 获取已处理的版本列表
get_processed_tags() {
  if [[ -f "$RELEASE_JSON" ]]; then
      jq -r '.[].tag_name' "$RELEASE_JSON" 2>/dev/null || echo ""
  else
      echo ""
  fi
}

# 检测需要处理的新版本
detect_new_releases() {
  local api_data="$1"
  
  log_info "正在检测需要处理的版本..."
  
  # 如果指定了特定 tag，只处理该版本
  if [[ -n "$SPECIFIC_TAG" ]]; then
      log_info "指定处理版本: $SPECIFIC_TAG"
      echo "$api_data" | jq -r --arg tag "$SPECIFIC_TAG" \
          '.[] | select(.tag_name == $tag) | .tag_name'
      return
  fi
  
  # 获取已处理的版本列表
  local processed_tags
  processed_tags=$(get_processed_tags)
  
  local new_tags
  if [[ -n "$processed_tags" && "$FORCE_RESYNC" != "true" ]]; then
      # 过滤出新版本
      local processed_json
      processed_json=$(printf '%s\n' "$processed_tags" | jq -R . | jq -s .)
      new_tags=$(echo "$api_data" | jq -r --argjson processed \
          "$processed_json" \
          '.[] | select(.tag_name as $tag | $processed | index($tag) | not) | .tag_name')
  else
      # 如果强制重新同步或没有历史记录，处理最新的几个版本
      new_tags=$(echo "$api_data" | jq -r --argjson max "$MAX_RELEASES" '.[:$max] | .[].tag_name')
  fi
  
  if [[ -z "$new_tags" ]]; then
      log_info "没有发现新版本需要处理"
  else
      local count=$(echo "$new_tags" | grep -c . || echo "0")
      log_success "发现 $count 个新版本需要处理"
  fi
  
  echo "$new_tags"
}

# 带重试机制的文件下载
download_file_with_retry() {
  local url="$1"
  local target_file="$2"
  local expected_size="$3"
  local max_retries=3
  local retry_count=0
  
  while [[ $retry_count -lt $max_retries ]]; do
      # 下载文件
      if curl -L -o "$target_file" \
          -H "Accept: application/octet-stream" \
          --connect-timeout 30 \
          --max-time 300 \
          --retry 2 \
          --retry-delay 5 \
          --silent \
          --show-error \
          "$url"; then
          
          # 验证文件大小
          if [[ -f "$target_file" ]]; then
              local actual_size
              actual_size=$(stat -c%s "$target_file" 2>/dev/null) || actual_size=$(stat -f%z "$target_file" 2>/dev/null) || actual_size="0"
              
              if [[ "$actual_size" -eq "$expected_size" ]]; then
                  return 0  # 下载成功
              else
                  log_warning "文件大小不匹配: 期望 $expected_size，实际 $actual_size"
                  rm -f "$target_file"
              fi
          fi
      fi
      
      ((retry_count++))
      if [[ $retry_count -lt $max_retries ]]; then
          log_warning "重试 $retry_count/$max_retries..."
          sleep $((retry_count * 2))
      fi
  done
  
  return 1  # 下载失败
}

# 下载指定 release 的 checksum 文件
download_checksum_files() {
  local tag_name="$1"
  local api_data="$2"
  
  log_info "🔍 处理版本: $tag_name"
  
  # 创建版本目录
  local target_dir="${CHECKSUM_DIR}/${tag_name}"
  mkdir -p "$target_dir"
  
  # 提取该版本的 assets 信息
  local release_data
  release_data=$(echo "$api_data" | jq --arg tag "$tag_name" '.[] | select(.tag_name == $tag)')
  
  if [[ -z "$release_data" || "$release_data" == "null" ]]; then
      log_warning "版本 $tag_name 未找到"
      return 1
  fi
  
  local assets
  assets=$(echo "$release_data" | jq -r '.assets[]')
  
  if [[ -z "$assets" || "$assets" == "null" ]]; then
      log_warning "版本 $tag_name 没有找到 assets"
      return 0
  fi
  
  # 筛选并下载 sha256sum- 开头的文件
  local checksum_files
  checksum_files=$(echo "$release_data" | jq -r \
      '.assets[] | select(.name | startswith("sha256sum-")) | 
       "\(.name)|\(.browser_download_url)|\(.size)"')
  
  if [[ -z "$checksum_files" ]]; then
      log_warning "版本 $tag_name 没有找到 checksum 文件"
      return 0
  fi
  
  local downloaded_count=0
  local total_size=0
  local failed_count=0
  
  # 逐个下载 checksum 文件
  while IFS='|' read -r filename download_url file_size; do
      [[ -z "$filename" ]] && continue
      
      local target_file="$target_dir/$filename"
      echo "    📥 下载: $filename ($(format_size $file_size))"
      
      # 下载文件并验证
      if download_file_with_retry "$download_url" "$target_file" "$file_size"; then
          downloaded_count=$((downloaded_count + 1))
          total_size=$((total_size + file_size))
          echo "    ✅ 完成: $filename"
      else
          echo "    ❌ 失败: $filename"
          failed_count=$((failed_count + 1))
      fi
  done <<< "$checksum_files"
  
  if [[ $downloaded_count -gt 0 ]]; then
      log_success "版本 $tag_name: 下载了 $downloaded_count 个文件，总大小 $(format_size $total_size)"
  fi
  
  if [[ $failed_count -gt 0 ]]; then
      log_warning "版本 $tag_name: $failed_count 个文件下载失败"
  fi
  
  return 0
}

# 更新 release.json 文件
update_release_json() {
  local api_data="$1"
  
  log_info "更新 release.json 文件..."
  
  # 确保目录存在
  mkdir -p "$TARGET_DIR"
  
  # 保存完整的 API 响应
  echo "$api_data" > "$RELEASE_JSON"
  
  log_success "release.json 已更新"
}

# 创建目录索引文件
create_directory_index() {
  local index_file="${CHECKSUM_DIR}/README.md"
  
  log_info "创建目录索引文件..."
  
  cat > "$index_file" << 'EOF'
# ChimeraOS Checksums

这个目录包含了从 [3003n/chimeraos](https://github.com/3003n/chimeraos) 同步的 release checksum 文件。

## 目录结构

每个 release tag 对应一个子目录，包含该版本的所有 SHA256 checksum 文件：

```
checksum/
├── v50-4/
│   ├── sha256sum-kde.txt
│   ├── sha256sum-kde-nv.txt
│   └── sha256sum-cinnamon.txt
└── v49-5/
  ├── sha256sum-kde.txt
  └── sha256sum-cinnamon.txt
```

## 最新版本

EOF
  
  # 添加最新版本信息
  if [[ -f "$RELEASE_JSON" ]]; then
      local latest_tag
      latest_tag=$(jq -r '.[0].tag_name' "$RELEASE_JSON" 2>/dev/null || echo "")
      
      if [[ -n "$latest_tag" && "$latest_tag" != "null" ]]; then
          echo "最新版本: **$latest_tag**" >> "$index_file"
          echo "" >> "$index_file"
          
          # 列出最新版本的文件
          if [[ -d "${CHECKSUM_DIR}/$latest_tag" ]]; then
              echo "最新版本包含的 checksum 文件：" >> "$index_file"
              # 使用更安全的方法列出文件
              local txt_files
              txt_files=$(find "${CHECKSUM_DIR}/$latest_tag" -name "*.txt" -type f 2>/dev/null || true)
              if [[ -n "$txt_files" ]]; then
                  while IFS= read -r file; do
                      [[ -f "$file" ]] && echo "- $(basename "$file")" >> "$index_file"
                  done <<< "$txt_files"
              fi
          fi
      fi
  fi
  
  echo "" >> "$index_file"
  echo "---" >> "$index_file"
  echo "*最后更新: $(date -u '+%Y-%m-%d %H:%M:%S UTC')*" >> "$index_file"
  
  log_success "目录索引已创建"
}

# 清理和维护目录结构
manage_directory_structure() {
  log_info "管理目录结构..."
  
  # 确保基础目录存在
  mkdir -p "$CHECKSUM_DIR"
  
  # 清理空目录（可选）
  find "$CHECKSUM_DIR" -type d -empty -delete 2>/dev/null || true
  
  # 生成目录索引
  if ! create_directory_index; then
      log_warning "创建目录索引失败"
      return 1
  fi
  
  return 0
}

# 主函数
main() {
  local start_time
  start_time=$(date +%s)
  
  log_info "🚀 开始同步 SK-ChimeraOS releases..."
  log_info "触发方式: $TRIGGER_TYPE"
  [[ -n "$SPECIFIC_TAG" ]] && log_info "指定标签: $SPECIFIC_TAG"
  [[ "$FORCE_RESYNC" == "true" ]] && log_info "强制重新同步: 是"
  log_info "最大处理数量: $MAX_RELEASES"
  echo ""
  
  # 获取 API 数据
  local api_data
  if ! api_data=$(get_releases_data); then
      log_error "获取 releases 数据失败"
      exit 1
  fi
  
  # 检测需要处理的版本
  local new_releases
  new_releases=$(detect_new_releases "$api_data")
  
  if [[ -z "$new_releases" ]]; then
      log_info "没有新版本需要处理，退出"
      exit 0
  fi
  
  # 更新 release.json
  update_release_json "$api_data"
  
  # 处理每个新版本
  local processed_count=0
  local failed_count=0
  
  while read -r tag; do
      [[ -z "$tag" ]] && continue
      
      if download_checksum_files "$tag" "$api_data"; then
          processed_count=$((processed_count + 1))
      else
          failed_count=$((failed_count + 1))
      fi
  done <<< "$new_releases"
  
  # 管理目录结构
  if ! manage_directory_structure; then
      log_warning "目录结构管理失败，但不影响主要功能"
  fi
  
  # 生成总结报告
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  echo ""
  log_success "📊 同步完成报告"
  echo "=================="
  echo "🔗 触发方式: $TRIGGER_TYPE"
  echo "⏱️  执行时间: ${duration}s"
  echo "📦 处理版本数: $processed_count"
  [[ $failed_count -gt 0 ]] && echo "❌ 失败版本数: $failed_count"
  
  if [[ $processed_count -gt 0 ]]; then
      echo "📋 处理的版本:"
      while read -r tag; do
          [[ -n "$tag" ]] && echo "   - $tag"
      done <<< "$new_releases"
  fi
  
  echo "📁 本地目录: $(pwd)/$TARGET_DIR/"
  echo "✅ 同步状态: 完成"
  
  if [[ $failed_count -gt 0 ]]; then
      log_warning "部分版本处理失败，请检查日志"
      exit 1
  fi
}

# 执行主函数
main "$@"