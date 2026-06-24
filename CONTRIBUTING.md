# 贡献指南

感谢你愿意改进 Abar。

## 开发环境

- Apple Silicon Mac
- macOS 14 或更高版本
- Node.js 20 或更高版本
- Swift 6 / Xcode Command Line Tools

```bash
git clone https://github.com/lanewulll/Abar.git
cd Abar
npm install
npm run check
npm test
```

## 提交修改

1. 先创建 Issue，描述问题、使用场景或建议。
2. 从 `main` 创建独立分支。
3. 行为修改必须补充测试。
4. 执行 `npm test` 和 `npm run build`。
5. 提交 Pull Request，并写明修改内容、验证步骤和界面影响。

请保持修改聚焦，不要在一个 Pull Request 中混入无关重构。

## 代码约定

- Swift 代码遵循现有命名和目录结构。
- Reporter 使用 Node.js 内置模块，除非必要，不增加运行时依赖。
- 不记录访问令牌、Cookie、Authorization Header 或完整认证文件内容。
- 不绕过 Codex Hook 的用户信任步骤。
- 新增配置必须同时更新中文 README。

## Commit 建议

推荐使用简短的 Conventional Commit 风格：

```text
feat: add login item support
fix: refresh project skill path after hook event
docs: clarify hook installation
test: cover invalid local port
```
