# SK-API-Info

🚀 **SK-ChimeraOS Release Information Sync System**

这个仓库提供了一个自动化同步系统，用于从 [3003n/chimeraos](https://github.com/3003n/chimeraos) 仓库同步 release 信息和 checksum 文件。

## ✨ 特性

- 🔄 **实时同步**: 当 ChimeraOS 发布新版本时自动触发同步
- 🎯 **手动控制**: 支持参数化的手动触发同步
- ⏰ **定时备份**: 每日定时检查，确保不遗漏任何版本
- 📁 **智能增量**: 只下载新版本，避免重复处理
- 🛡️ **健壮处理**: 重试机制和错误恢复
- 📊 **详细日志**: 完整的执行报告和状态追踪

## 📂 目录结构

```
sk-api-info/
├── .github/
│   ├── workflows/
│   │   └── sync-sk-chimeraos.yml     # 主同步 workflow
│   └── scripts/
│       └── sync-chimeraos.sh         # 核心同步脚本
├── sk-chimeraos/                     # 同步的数据目录
│   ├── release.json                  # GitHub API 响应
│   └── checksum/                     # checksum 文件
│       ├── README.md                 # 目录索引
│       ├── 50-4_f6d09f1/            # 各版本目录
│       │   ├── sha256sum-kde.txt
│       │   ├── sha256sum-gnome.txt
│       │   └── ...
│       └── ...
├── docs/                             # 文档
│   ├── SETUP_GUIDE.md               # 详细设置指南
│   └── 3003n-chimeraos-trigger-workflow.yml  # 源仓库的触发 workflow
├── test-sync.sh                     # 测试脚本
└── README.md                        # 本文件
```

## 🚀 快速开始

### 手动触发同步

1. 访问本仓库的 [Actions](../../actions) 页面
2. 选择 "Sync SK-ChimeraOS" workflow
3. 点击 "Run workflow"
4. 可选择特定参数：
   - **specific_tag**: 同步指定版本
   - **force_resync**: 强制重新同步
   - **max_releases**: 最大处理数量

### 自动同步设置

要启用自动同步，需要在 `3003n/chimeraos` 仓库中进行配置。详细步骤请参考 [设置指南](docs/SETUP_GUIDE.md)。

## 📊 同步数据

### release.json

包含完整的 GitHub API 响应，包括所有 release 的详细信息：
- 版本标签和发布时间
- Release 描述和作者信息
- Assets 列表和下载链接
- 文件大小和校验和信息

### checksum 文件

每个版本目录包含该版本的所有 SHA256 checksum 文件：
- `sha256sum-kde.txt` - KDE 版本
- `sha256sum-gnome.txt` - GNOME 版本
- `sha256sum-cinnamon.txt` - Cinnamon 版本
- `sha256sum-cosmic.txt` - Cosmic 版本
- `sha256sum-hyprland.txt` - Hyprland 版本
- 以及其他变体（如 NVIDIA 版本）

## 🔧 本地测试

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/sk-api-info.git
cd sk-api-info

# 运行测试脚本
./test-sync.sh

# 或直接运行同步脚本
./.github/scripts/sync-chimeraos.sh manual "" false 3
```

## 📖 文档

- [详细设置指南](docs/SETUP_GUIDE.md) - 完整的安装和配置步骤
- [故障排除](docs/SETUP_GUIDE.md#🔧-故障排除) - 常见问题解决方案

## 🔄 触发方式

| 触发方式 | 说明 | 频率 |
|---------|------|------|
| **repository_dispatch** | 实时响应新 release | 立即 |
| **workflow_dispatch** | 手动触发 | 按需 |
| **schedule** | 定时检查 | 每日 02:00 UTC |

## 📈 监控状态

- 🟢 **最新同步**: 检查 [Actions](../../actions) 页面的最新运行
- 📁 **数据状态**: 查看 [sk-chimeraos](sk-chimeraos/) 目录
- 📊 **版本信息**: 查看 [checksum 索引](sk-chimeraos/checksum/README.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个同步系统！

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

*本仓库是 [SK-ChimeraOS](https://github.com/3003n/chimeraos) 项目的配套工具，旨在提供便捷的 release 信息访问。*