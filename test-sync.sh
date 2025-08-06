#!/bin/bash

# 简单的测试脚本来验证同步功能

set -euo pipefail

echo "🧪 测试 SK-ChimeraOS 同步脚本"
echo "================================"

# 检查必要的工具
echo "检查必要工具..."
for tool in curl jq; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "❌ 缺少工具: $tool"
        exit 1
    else
        echo "✅ $tool 可用"
    fi
done

# 测试 API 连接
echo ""
echo "测试 GitHub API 连接..."
api_url="https://api.github.com/repos/3003n/chimeraos/releases?per_page=3"

if api_response=$(curl -s -H "Accept: application/vnd.github+json" "$api_url"); then
    if echo "$api_response" | jq empty 2>/dev/null; then
        release_count=$(echo "$api_response" | jq '. | length')
        echo "✅ API 连接成功，获取到 $release_count 个 releases"
        
        # 显示最新的 release 信息
        latest_tag=$(echo "$api_response" | jq -r '.[0].tag_name' 2>/dev/null || echo "unknown")
        echo "📦 最新版本: $latest_tag"
        
        # 检查是否有 checksum 文件
        checksum_count=$(echo "$api_response" | jq '[.[0].assets[] | select(.name | startswith("sha256sum-"))] | length' 2>/dev/null || echo "0")
        echo "🔢 最新版本的 checksum 文件数: $checksum_count"
        
        if [[ $checksum_count -gt 0 ]]; then
            echo "📋 Checksum 文件列表:"
            echo "$api_response" | jq -r '.[0].assets[] | select(.name | startswith("sha256sum-")) | "  - \(.name) (\(.size) bytes)"' 2>/dev/null || echo "  无法解析文件列表"
        fi
    else
        echo "❌ API 返回的不是有效 JSON"
        echo "响应前100字符: ${api_response:0:100}..."
        exit 1
    fi
else
    echo "❌ API 请求失败"
    exit 1
fi

echo ""
echo "🎯 准备运行同步脚本测试..."
echo "注意: 这将实际下载文件到 sk-chimeraos/ 目录"
read -p "是否继续? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "测试取消"
    exit 0
fi

# 运行同步脚本（只处理最新1个版本）
echo ""
echo "运行同步脚本..."
if ./.github/scripts/sync-chimeraos.sh manual "" false 1; then
    echo ""
    echo "✅ 同步脚本执行成功"
    
    # 检查结果
    if [[ -f "sk-chimeraos/release.json" ]]; then
        echo "✅ release.json 文件已创建"
        latest_in_file=$(jq -r '.[0].tag_name' sk-chimeraos/release.json 2>/dev/null || echo "unknown")
        echo "📦 文件中最新版本: $latest_in_file"
    fi
    
    if [[ -d "sk-chimeraos/checksum" ]]; then
        echo "✅ checksum 目录已创建"
        dir_count=$(find sk-chimeraos/checksum -maxdepth 1 -type d | wc -l)
        echo "📁 版本目录数: $((dir_count - 1))"
        
        if [[ -f "sk-chimeraos/checksum/README.md" ]]; then
            echo "✅ README.md 索引文件已创建"
        fi
    fi
    
    echo ""
    echo "📊 测试完成总结:"
    echo "- API 连接: ✅"
    echo "- 脚本执行: ✅"
    echo "- 文件下载: $([ -d sk-chimeraos/checksum ] && echo '✅' || echo '❌')"
    echo "- 结构创建: $([ -f sk-chimeraos/checksum/README.md ] && echo '✅' || echo '❌')"
    
else
    echo "❌ 同步脚本执行失败"
    echo "请检查错误信息并修复问题"
    exit 1
fi