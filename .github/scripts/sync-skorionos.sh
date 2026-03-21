#!/bin/bash

# SkorionOS Sync Script
# 用于同步 SkorionOS/skorionos 仓库的 release 信息和 checksum 文件

set -euo pipefail

# 脚本参数
TRIGGER_TYPE="${1:-schedule}"
SPECIFIC_TAG="${2:-}"
FORCE_RESYNC="${3:-false}"
MAX_RELEASES="${4:-10}"
ENABLE_CLEANUP="${5:-auto}"  # auto/true/false - 是否启用清理功能

MAX_RELEASES="$(printf "%.0f\n" $MAX_RELEASES)"

# 参数验证
if ! [[ "$MAX_RELEASES" =~ ^[0-9]+$ ]]; then
  echo "❌ MAX_RELEASES 必须是数字: $MAX_RELEASES" >&2
  exit 1
fi

if [[ "$ENABLE_CLEANUP" != "auto" && "$ENABLE_CLEANUP" != "true" && "$ENABLE_CLEANUP" != "false" ]]; then
  echo "❌ ENABLE_CLEANUP 必须是 auto/true/false: $ENABLE_CLEANUP" >&2
  exit 1
fi

# 计算 API 获取数量的智能函数
calculate_api_limit() {
  local local_count=0
  
  # 统计本地 checksum 目录数量
  if [[ -d "$CHECKSUM_DIR" ]]; then
    local_count=$(find "$CHECKSUM_DIR" -maxdepth 1 -type d -name "*_*" 2>/dev/null | wc -l)
  fi
  
  # 计算需要的 API 数据量：本地数量 + 缓冲区 (20个)
  local api_limit=$((local_count + 20))
  
  # 返回 max(计算值, MAX_RELEASES) 确保不小于用户指定值
  if [[ $api_limit -gt $MAX_RELEASES ]]; then
    echo $api_limit
  else
    echo $MAX_RELEASES
  fi
}

# 常量配置
readonly SkorionOS_REPO="SkorionOS/skorionos"
readonly API_BASE_URL="https://api.github.com"
readonly RELEASES_API_URL="${API_BASE_URL}/repos/${SkorionOS_REPO}/releases"
readonly TARGET_DIR="skorionos"
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
  log_info "正在获取 SkorionOS releases 信息..."
  
  # 计算实际需要的 API 数据量
  local api_limit
  api_limit=$(calculate_api_limit)
  
  log_info "API 请求数量: $api_limit (本地目录: $(find "$CHECKSUM_DIR" -maxdepth 1 -type d -name "*_*" 2>/dev/null | wc -l), 处理限制: $MAX_RELEASES)"
  
  local api_response
  if ! api_response=$(curl -s \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "${RELEASES_API_URL}?per_page=${api_limit}" 2>/dev/null); then
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
      # 过滤出新版本，但限制处理数量
      local processed_json
      processed_json=$(printf '%s\n' "$processed_tags" | jq -R . | jq -s .)
      new_tags=$(echo "$api_data" | jq -r --argjson processed \
          "$processed_json" --argjson max "$MAX_RELEASES" \
          '.[] | select(.tag_name as $tag | $processed | index($tag) | not) | .tag_name' | head -n "$MAX_RELEASES")
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

# 下载指定 release 的 delta-manifest 文件
download_delta_manifest_files() {
  local tag_name="$1"
  local api_data="$2"
  
  local delta_dir="${TARGET_DIR}/delta/${tag_name}"
  
  local release_data
  release_data=$(echo "$api_data" | jq --arg tag "$tag_name" '.[] | select(.tag_name == $tag)')
  
  if [[ -z "$release_data" || "$release_data" == "null" ]]; then
      return 0
  fi
  
  local delta_files
  delta_files=$(echo "$release_data" | jq -r \
      '.assets[] | select(.name | startswith("delta-manifest-")) | 
       "\(.name)|\(.browser_download_url)|\(.size)"')
  
  if [[ -z "$delta_files" ]]; then
      return 0
  fi
  
  mkdir -p "$delta_dir"
  
  local downloaded_count=0
  
  while IFS='|' read -r filename download_url file_size; do
      [[ -z "$filename" ]] && continue
      
      local target_file="$delta_dir/$filename"
      echo "    📥 Delta manifest: $filename ($(format_size $file_size))"
      
      if download_file_with_retry "$download_url" "$target_file" "$file_size"; then
          downloaded_count=$((downloaded_count + 1))
          echo "    ✅ 完成: $filename"
      else
          echo "    ❌ 失败: $filename"
      fi
  done <<< "$delta_files"
  
  if [[ $downloaded_count -gt 0 ]]; then
      log_success "版本 $tag_name: 下载了 $downloaded_count 个 delta-manifest 文件"
  fi
  
  return 0
}

# 过滤 API 数据，只保留必要字段
filter_api_data() {
  local api_data="$1"
  
  # 使用 jq 过滤掉不必要的字段，只保留 get_img_url 函数需要的字段
  echo "$api_data" | jq '[
    .[] | {
      created_at,
      prerelease,
      name,
      tag_name,
      assets: [
        .assets[] | {
          browser_download_url,
          state,
          name,
          size
        }
      ]
    }
  ]'
}

# 更新 release.json 文件
update_release_json() {
  local api_data="$1"
  
  log_info "更新 release.json 文件..."
  
  # 确保目录存在
  mkdir -p "$TARGET_DIR"
  
  # 过滤并保存精简的 API 响应
  local filtered_data
  if ! filtered_data=$(filter_api_data "$api_data"); then
    log_error "数据过滤失败"
    return 1
  fi
  
  echo "$filtered_data" > "$RELEASE_JSON"
  
  # 计算文件大小
  local file_size
  file_size=$(stat -c%s "$RELEASE_JSON" 2>/dev/null || echo "0")
  local formatted_size
  formatted_size=$(format_size "$file_size")
  
  log_success "release.json 已更新 (精简后: $formatted_size)"
}

# 创建目录索引文件
create_directory_index() {
  local index_file="${CHECKSUM_DIR}/README.md"
  
  log_info "创建目录索引文件..."
  
  cat > "$index_file" << 'EOF'
# SkorionOS Checksums

这个目录包含了从 [SkorionOS/skorionos](https://github.com/SkorionOS/skorionos) 同步的 release checksum 文件。

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

# 判断是否应该执行清理
should_cleanup() {
  local api_count="$1"
  local local_count="$2"
  
  case "$ENABLE_CLEANUP" in
    "true")
      return 0  # 强制清理
      ;;
    "false")
      return 1  # 禁用清理
      ;;
    "auto")
      # 智能判断：只有 API 数据 >= 本地目录数时才清理
      if [[ $api_count -ge $local_count ]]; then
        return 0
      else
        return 1
      fi
      ;;
  esac
}

# 清理多余的 checksum 目录
cleanup_obsolete_checksums() {
  local api_data="$1"
  local processed_versions="$2"  # 新增：实际处理的版本列表
  
  # 统计数量
  local api_count
  api_count=$(echo "$api_data" | jq '. | length')
  local local_count=0
  if [[ -d "$CHECKSUM_DIR" ]]; then
    local_count=$(find "$CHECKSUM_DIR" -maxdepth 1 -type d -name "*_*" 2>/dev/null | wc -l)
  fi
  
  # 判断是否应该清理
  if ! should_cleanup "$api_count" "$local_count"; then
    log_warning "跳过清理: API 数据($api_count) < 本地目录($local_count)，或清理被禁用"
    log_info "如需强制清理，请使用参数: ENABLE_CLEANUP=true"
    return 0
  fi
  
  log_info "清理多余的 checksum 目录... (API: $api_count, 本地: $local_count)"
  
  # 获取 API 中的所有有效版本标签
  local api_tags
  api_tags=$(echo "$api_data" | jq -r '.[] | .tag_name' | sort)
  
  # 如果有处理过的版本列表，将其加入到保留列表中
  local keep_tags="$api_tags"
  if [[ -n "$processed_versions" ]]; then
    # 合并API标签和已处理版本，去重排序
    keep_tags=$(echo -e "$api_tags\n$processed_versions" | sort -u)
    log_info "保留标签: API($api_count) + 已处理($(echo "$processed_versions" | wc -l)) = $(echo "$keep_tags" | wc -l)"
  fi
  
  if [[ -z "$keep_tags" ]]; then
    log_warning "无法确定需要保留的版本标签"
    return 1
  fi
  
  # 获取本地 checksum 目录列表
  local local_dirs
  if [[ -d "$CHECKSUM_DIR" ]]; then
    local_dirs=$(find "$CHECKSUM_DIR" -maxdepth 1 -type d -name "*_*" -exec basename {} \; | sort)
  else
    log_info "checksum 目录不存在，跳过清理"
    return 0
  fi
  
  if [[ -z "$local_dirs" ]]; then
    log_info "没有本地 checksum 目录需要清理"
    return 0
  fi
  
  # 找出需要删除的目录（本地有但保留列表中没有的）
  local dirs_to_delete
  dirs_to_delete=$(comm -23 <(echo "$local_dirs") <(echo "$keep_tags"))
  
  if [[ -z "$dirs_to_delete" ]]; then
    log_success "所有本地目录都与 API 数据一致"
    return 0
  fi
  
  # 删除多余的目录
  local deleted_count=0
  while read -r dir_name; do
    [[ -z "$dir_name" ]] && continue
    
    local dir_path="${CHECKSUM_DIR}/${dir_name}"
    if [[ -d "$dir_path" ]]; then
      log_info "删除多余目录: $dir_name"
      rm -rf "$dir_path"
      deleted_count=$((deleted_count + 1))
    fi
  done <<< "$dirs_to_delete"
  
  if [[ $deleted_count -gt 0 ]]; then
    log_success "已清理 $deleted_count 个多余的 checksum 目录"
  fi
  
  return 0
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
  
  log_info "🚀 开始同步 SK-SkorionOS releases..."
  log_info "触发方式: $TRIGGER_TYPE"
  [[ -n "$SPECIFIC_TAG" ]] && log_info "指定标签: $SPECIFIC_TAG"
  [[ "$FORCE_RESYNC" == "true" ]] && log_info "强制重新同步: 是"
  log_info "最大处理数量: $MAX_RELEASES"
  log_info "清理模式: $ENABLE_CLEANUP"
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
  local processed_versions=""  # 收集已处理的版本
  
  while read -r tag; do
      [[ -z "$tag" ]] && continue
      
      if download_checksum_files "$tag" "$api_data"; then
          processed_count=$((processed_count + 1))
          # 添加到已处理版本列表
          if [[ -z "$processed_versions" ]]; then
            processed_versions="$tag"
          else
            processed_versions="$processed_versions"$'\n'"$tag"
          fi
      else
          failed_count=$((failed_count + 1))
      fi

      # Also sync delta-manifest files if available
      download_delta_manifest_files "$tag" "$api_data" || true
  done <<< "$new_releases"
  
  # 清理多余的 checksum 目录，传递已处理的版本列表
  if ! cleanup_obsolete_checksums "$api_data" "$processed_versions"; then
      log_warning "清理多余目录失败，但不影响主要功能"
  fi
  
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