# SK-ChimeraOS 同步系统设置指南

这个指南将帮助您设置完整的 ChimeraOS releases 自动同步系统。

## 🎯 系统概述

该系统实现了从 `3003n/skorionos` 仓库到 `sk-api-info` 仓库的自动同步，包括：

- ✅ 实时同步：当 ChimeraOS 发布新版本时自动触发
- ✅ 手动同步：支持参数化的手动触发
- ✅ 定时同步：每日定时检查作为备用
- ✅ 智能增量：只下载新版本的 checksum 文件
- ✅ 健壮处理：重试机制和错误恢复

## 📋 设置步骤

### 1. 在 3003n/skorionos 仓库中设置

#### 1.1 创建 Personal Access Token (PAT)

⚠️ **重要说明**：PAT 需要在**您的个人 GitHub 账户设置**中创建，不是在组织仓库中创建。

**前提条件**：您需要是 `3003n` 组织的 Owner 或有足够权限，同时拥有目标仓库的访问权限。

1. 访问**您的个人账户** GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. 点击 "Generate new token (classic)"
3. 设置权限：
   - ✅ `repo` (完整访问权限) - 这将允许 PAT 访问您有权限的所有仓库
   - ✅ `workflow` (如果需要触发 workflow)
4. 复制生成的 token

💡 **权限原理**：PAT 继承您个人账户的权限，因为您同时拥有组织仓库和个人仓库的权限，所以 PAT 可以在它们之间建立连接。

#### 1.2 在 3003n/skorionos 仓库添加 Secret

1. 访问 `3003n/skorionos` 仓库设置
2. 进入 Secrets and variables → Actions
3. 添加新的 Repository secret：
   - Name: `PAT_SK_API_INFO`
   - Value: 上面创建的 PAT token

#### 1.3 添加触发 Workflow

将 `docs/3003n-skorionos-trigger-workflow.yml` 文件复制到 `3003n/skorionos` 仓库的 `.github/workflows/notify-sk-api-info.yml`

⚠️ **重要**: 修改文件中的 `YOUR_USERNAME` 为实际的用户名！

### 2. 在 sk-api-info 仓库中验证

已经创建的文件：
- ✅ `.github/workflows/sync-skorionos.yml` - 主同步 workflow
- ✅ `.github/scripts/sync-skorionos.sh` - 同步脚本

## 🚀 使用方法

### 自动触发（推荐）

当您在 `3003n/skorionos` 发布新 release 时：
1. GitHub 自动触发 `notify-sk-api-info.yml` workflow
2. 该 workflow 向 `sk-api-info` 发送 `repository_dispatch` 事件
3. `sk-api-info` 自动开始同步新版本的 checksum 文件

### 手动触发

在 `sk-api-info` 仓库的 Actions 页面：
1. 选择 "Sync SK-ChimeraOS" workflow
2. 点击 "Run workflow"
3. 可选参数：
   - **specific_tag**: 指定要同步的版本
   - **force_resync**: 强制重新同步所有版本
   - **max_releases**: 最大处理版本数

### 定时同步

系统每天 UTC 02:00 自动检查一次，作为安全网防止遗漏。

## 📂 输出结构

同步完成后，将在 `sk-api-info` 仓库中生成：

```
skorionos/
├── release.json                     # 完整的 GitHub API 响应
└── checksum/                        # checksum 文件根目录
    ├── README.md                    # 目录说明和索引
    ├── 50-4_f6d09f1/               # 版本目录
    │   ├── sha256sum-kde.txt        # KDE 版本 checksum
    │   ├── sha256sum-kde-nv.txt     # KDE NVIDIA 版本 checksum
    │   └── sha256sum-cinnamon.txt   # Cinnamon 版本 checksum
    └── 49-5_8bcce3c/
        ├── sha256sum-kde.txt
        └── sha256sum-cinnamon.txt
```

## 🔧 故障排除

### 问题 1: 自动触发不工作

**可能原因:**
- PAT token 权限不足
- Secret 名称不正确
- 目标仓库名称错误

**解决方案:**
1. 检查 `3003n/skorionos` 仓库的 `PAT_SK_API_INFO` secret
2. 确认 PAT token 有 `repo` 权限
3. 检查 workflow 文件中的仓库名称

### 问题 2: 下载文件失败

**可能原因:**
- 网络连接问题
- GitHub API 限制
- 文件不存在

**解决方案:**
1. 脚本有重试机制，通常会自动恢复
2. 可以手动重新运行 workflow
3. 检查 GitHub API 状态页面

### 问题 3: 权限错误

**解决方案:**
1. 确保 `GITHUB_TOKEN` 有足够权限
2. 检查仓库设置中的 Actions 权限
3. 确认 workflow 文件语法正确

## 🧪 测试验证

### 测试手动触发

1. 在 `sk-api-info` 仓库运行手动同步
2. 指定一个已知存在的 tag
3. 检查是否成功下载 checksum 文件

### 测试自动触发

1. 在 `3003n/skorionos` 创建一个测试 release
2. 检查是否触发了 `sk-api-info` 的同步
3. 验证同步的文件是否正确

## 📊 监控和日志

### 查看执行日志

1. 访问 `sk-api-info` 仓库的 Actions 页面
2. 选择具体的 workflow run
3. 查看详细的执行日志和错误信息

### 监控同步状态

- 检查 `skorionos/release.json` 文件的更新时间
- 查看 `skorionos/checksum/README.md` 中的最新版本信息
- 验证目录结构是否完整

## 🔒 安全注意事项

1. **PAT Token 安全**：
   - 使用最小权限原则
   - 定期轮换 token
   - 不要在代码中硬编码

2. **仓库权限**：
   - 确保只有授权用户能访问 secrets
   - 定期审查协作者权限

3. **监控异常**：
   - 关注 workflow 失败通知
   - 检查异常的同步行为

## 📞 支持

如果遇到问题：
1. 检查 GitHub Actions 的执行日志
2. 查看本文档的故障排除章节
3. 确认所有配置步骤是否正确完成

---

*该系统设计为自动化和健壮性，正常情况下无需人工干预。*