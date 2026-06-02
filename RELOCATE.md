# 此目录不应留在 ContentMRS 下

sub2api 是 **workspace 级公共基础设施**，真源路径应为：

**`E:\My Project\sub2api`**

当前若仍在本路径，多为历史副本或 junction 目标。停服后执行：

```powershell
pwsh -File "E:\My Project\ContentMRS\scripts\move-sub2api-to-workspace-root.ps1"
```

文档：`ContentMRS/docs/infrastructure-sub2api.md`
