param(
    [string]$BasePath = "/time-note"
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Time-Note Export für GitHub Pages ===" -ForegroundColor Cyan
Write-Host "Base path: $BasePath"
Write-Host "Output:    docs/"
Write-Host ""

# 1. Install adapter-static if needed
if (-not (Test-Path 'node_modules/@sveltejs/adapter-static')) {
    Write-Host "[1/4] Installing @sveltejs/adapter-static..." -ForegroundColor Yellow
    npm install -D @sveltejs/adapter-static
} else {
    Write-Host "[1/4] @sveltejs/adapter-static already installed" -ForegroundColor Green
}

# 2. Backup config and create export config
Write-Host "[2/4] Creating export config..." -ForegroundColor Yellow
$origConfig = Get-Content 'svelte.config.js' -Raw
$exportConfig = @"
import adapter from '@sveltejs/adapter-static';
const config = {
	compilerOptions: {
		runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true)
	},
	kit: {
		paths: { base: '$BasePath' },
		adapter: adapter({ pages: 'build', assets: 'build', fallback: null, precompress: false, strict: true })
	}
};
export default config;
"@

Set-Content 'svelte.config.js' $exportConfig
Set-Content 'src/routes/+layout.ts' "export const prerender = true;`n"

try {
    # 3. Build
    Write-Host "[3/4] Building static export..." -ForegroundColor Yellow
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }

    # 4. Deploy to docs/ folder
    Write-Host "[4/4] Deploying to docs/..." -ForegroundColor Yellow

    # Clear docs/
    if (Test-Path 'docs') {
        Remove-Item 'docs/*' -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory -Path 'docs' | Out-Null
    }

    # Copy everything from build/ to docs/
    Copy-Item 'build/*' 'docs/' -Recurse -Force

    # Disable Jekyll: without this, GitHub Pages ignores _app/ folder
    Set-Content 'docs/.nojekyll' ''

    Write-Host ""
    Write-Host "=== Done! ===" -ForegroundColor Cyan
    $size = (Get-ChildItem 'docs' -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1KB
    Write-Host "Deployed to docs/ ($([math]::Round($size, 0)) KB)" -ForegroundColor Green

} finally {
    # Restore original config
    Set-Content 'svelte.config.js' $origConfig
    Remove-Item 'src/routes/+layout.ts' -Force -ErrorAction SilentlyContinue
    Remove-Item 'build' -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned up" -ForegroundColor DarkGray
}
