#!/bin/bash
set -e

echo "=== 八股文笔记 博客初始化 ==="

# 1. 克隆 neopost 主题
if [ ! -d "themes/neopost" ]; then
    echo "克隆 neopost 主题..."
    git clone https://github.com/salatine/neopost.git themes/neopost
fi

# 2. 复制主题 archetypes
mkdir -p archetypes/sidebar archetypes/welcome-header
cp -n themes/neopost/archetypes/sidebar/* archetypes/sidebar/ 2>/dev/null || true
cp -n themes/neopost/archetypes/welcome-header/* archetypes/welcome-header/ 2>/dev/null || true

# 3. 替换 baseURL 占位符
read -p "GitHub 用户名: " github_user
read -p "仓库名: " repo_name
sed -i "s|REPLACE_USERNAME|$github_user|g" hugo.yaml
sed -i "s|REPLACE_REPO|$repo_name|g" hugo.yaml
sed -i "s|REPLACE_USERNAME|$github_user|g" static/admin/config.yml
sed -i "s|REPLACE_REPO|$repo_name|g" static/admin/config.yml
sed -i "s|REPLACE_USERNAME|$github_user|g" content/sidebar/_index.md

echo ""
echo "=== 初始化完成 ==="
echo "本地运行: hugo server -D"
echo "浏览器打开: http://localhost:1313"
echo "CMS 后台: http://localhost:1313/admin"

# 4. 提示 git 初始化
echo ""
echo "=== 推送到 GitHub ==="
echo "1. 在 GitHub 创建仓库: $repo_name"
echo "2. 设置 GitHub Pages source 为 'GitHub Actions'"
echo "3. 运行:"
echo "   git remote add origin https://github.com/$github_user/$repo_name.git"
echo "   git add ."
echo "   git commit -m 'init blog'"
echo "   git push -u origin main"
echo ""
echo "=== Decap CMS OAuth 配置 ==="
echo "如需 CMS 在线编辑，需配置 GitHub OAuth:"
echo "1. GitHub Settings → Developer settings → OAuth Apps → New OAuth App"
echo "2. Homepage URL: https://decapcms.org"
echo "3. Authorization callback URL: https://decapcms.org/oauth/"
echo "4. 将 client_id 填入 static/admin/config.yml"
