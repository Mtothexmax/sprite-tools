<script lang="ts">
	import type { SpriteLabel } from '$lib/types';

	function autoFocus(node: HTMLInputElement) {
		node.focus();
	}

	type HandleType = 'tl' | 'tc' | 'tr' | 'ml' | 'mr' | 'bl' | 'bc' | 'br';

	interface Handle {
		type: HandleType;
		x: number;
		y: number;
	}

	interface ResizeState {
		idx: number;
		handle: HandleType;
		startMX: number;
		startMY: number;
		label: SpriteLabel;
	}

	let { img = $bindable(null), labels = $bindable([]), hasImage = $bindable(false) } = $props();

	let canvasEl: HTMLCanvasElement = $state() as unknown as HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = $state(null);
	let checkerPattern: CanvasPattern | null = $state(null);
	let isDrawing = $state(false);
	let startX = 0, startY = 0, curX = 0, curY = 0;
	let selectedIdx = $state(-1);
	let selectedSet = $state<Set<number>>(new Set());
	let editIdx = $state(-1);
	let editNameVal = $state('');
	let zoom = $state(1);
	let panX = $state(0), panY = $state(0);
	let showLabelNames = $state(false);
	let galleryView = $state(false);
	let galleryZoom = $state(1);
	let resizeState: ResizeState | null = $state(null);
	let moveState: { idx: number; startMX: number; startMY: number; label: SpriteLabel } | null = $state(null);
	let hoverOverSelected = $state(false);
	let isPanning = $state(false);
	let panStartX = 0, panStartY = 0;
	let canvasCursor = $state('default');

	const MIN_SIZE = 4;

	function getCanvasCoords(e: MouseEvent): { x: number; y: number } {
		const r = canvasEl.getBoundingClientRect();
		return {
			x: (e.clientX - r.left) * (canvasEl.width / r.width),
			y: (e.clientY - r.top) * (canvasEl.height / r.height)
		};
	}

	function getHandles(l: SpriteLabel): Handle[] {
		const hw = l.width / 2, hh = l.height / 2;
		return [
			{ type: 'tl', x: l.x, y: l.y },
			{ type: 'tc', x: l.x + hw, y: l.y },
			{ type: 'tr', x: l.x + l.width, y: l.y },
			{ type: 'ml', x: l.x, y: l.y + hh },
			{ type: 'mr', x: l.x + l.width, y: l.y + hh },
			{ type: 'bl', x: l.x, y: l.y + l.height },
			{ type: 'bc', x: l.x + hw, y: l.y + l.height },
			{ type: 'br', x: l.x + l.width, y: l.y + l.height },
		];
	}

	function hitTestLabel(mx: number, my: number): number {
		for (let i = labels.length - 1; i >= 0; i--) {
			const l = labels[i];
			if (mx >= l.x && mx <= l.x + l.width && my >= l.y && my <= l.y + l.height) return i;
		}
		return -1;
	}

	function cursorForHandle(type: HandleType): string {
		const m: Record<HandleType, string> = {
			tl: 'nw-resize', tc: 'n-resize', tr: 'ne-resize',
			ml: 'w-resize', mr: 'e-resize',
			bl: 'sw-resize', bc: 's-resize', br: 'se-resize',
		};
		return m[type];
	}

	function updateCursor() {
		if (isPanning) { canvasCursor = 'grabbing'; return; }
		if (resizeState) { canvasCursor = cursorForHandle(resizeState.handle); return; }
		if (isDrawing) { canvasCursor = 'crosshair'; return; }
		if (hoverOverSelected) { canvasCursor = 'move'; return; }
		canvasCursor = 'default';
	}

	function redraw() {
		if (!ctx || !img || !checkerPattern || !canvasEl) return;
		ctx.fillStyle = checkerPattern;
		ctx.fillRect(0, 0, canvasEl.width, canvasEl.height);
		ctx.drawImage(img, 0, 0);

		for (let i = 0; i < labels.length; i++) {
			const l = labels[i];

			if (showLabelNames) {
				ctx.font = '13px monospace';
				const tw = ctx.measureText(l.name).width;
				ctx.fillStyle = 'rgba(0,0,0,0.7)';
				ctx.fillRect(l.x, l.y - 16, tw + 6, 18);
				ctx.fillStyle = '#ffffff';
				ctx.fillText(l.name, l.x + 3, l.y - 3);
			}
		}

		if (isDrawing) {
			const x = Math.min(startX, curX), y = Math.min(startY, curY);
			const w = Math.abs(curX - startX), h = Math.abs(curY - startY);
			ctx.strokeStyle = '#3b82f6';
			ctx.lineWidth = 2;
			ctx.setLineDash([6, 4]);
			ctx.strokeRect(x, y, w, h);
			ctx.setLineDash([]);
			ctx.fillStyle = 'rgba(59,130,246,0.1)';
			ctx.fillRect(x, y, w, h);
		}
	}

	function applyResize(orig: SpriteLabel, type: HandleType, dx: number, dy: number): SpriteLabel {
		let { x, y, width, height } = orig;
		switch (type) {
			case 'tl': x += dx; y += dy; width -= dx; height -= dy; break;
			case 'tc': y += dy; height -= dy; break;
			case 'tr': y += dy; width += dx; height -= dy; break;
			case 'ml': x += dx; width -= dx; break;
			case 'mr': width += dx; break;
			case 'bl': x += dx; width -= dx; height += dy; break;
			case 'bc': height += dy; break;
			case 'br': width += dx; height += dy; break;
		}
		if (width < MIN_SIZE) {
			if (type === 'tl' || type === 'ml' || type === 'bl') x -= MIN_SIZE - width;
			width = MIN_SIZE;
		}
		if (height < MIN_SIZE) {
			if (type === 'tl' || type === 'tc' || type === 'tr') y -= MIN_SIZE - height;
			height = MIN_SIZE;
		}
		return { ...orig, x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
	}

	function handleWheel(e: WheelEvent) {
		e.preventDefault();
		const r = canvasEl.getBoundingClientRect();
		const mx = e.clientX - r.left, my = e.clientY - r.top;
		const cx = mx / r.width * canvasEl.width;
		const cy = my / r.height * canvasEl.height;
		const delta = -e.deltaY * 0.001;
		const nz = Math.max(0.1, Math.min(20, zoom * (1 + delta)));
		panX = cx * zoom + panX - cx * nz;
		panY = cy * zoom + panY - cy * nz;
		zoom = nz;
	}

	function handleMD(e: MouseEvent) {
		if (!hasImage || !canvasEl) return;
		if (e.button === 1) {
			e.preventDefault();
			isPanning = true;
			isDrawing = false;
			panStartX = e.clientX - panX;
			panStartY = e.clientY - panY;
			updateCursor();
			return;
		}
		if (e.button !== 0) return;
		const p = getCanvasCoords(e);
		const hit = hitTestLabel(p.x, p.y);
		if (hit >= 0) {
			if (e.shiftKey) {
				const s = new Set(selectedSet);
				if (s.has(hit)) s.delete(hit); else s.add(hit);
				selectedSet = s;
				selectedIdx = hit;
			} else {
				selectedSet = new Set([hit]);
				selectedIdx = hit;
			}
			moveState = { idx: hit, startMX: p.x, startMY: p.y, label: { ...labels[hit] } };
			redraw();
			return;
		} else if (!e.shiftKey) {
			selectedSet = new Set();
		}
		startX = p.x; startY = p.y;
		curX = p.x; curY = p.y;
		isDrawing = true;
		updateCursor();
	}

	function handleMM(e: MouseEvent) {
		if (isPanning) {
			panX = e.clientX - panStartX;
			panY = e.clientY - panStartY;
			return;
		}
		if (resizeState) {
			const p = getCanvasCoords(e);
			const dx = p.x - resizeState.startMX;
			const dy = p.y - resizeState.startMY;
			const nl = [...labels];
			nl[resizeState.idx] = applyResize(resizeState.label, resizeState.handle, dx, dy);
			labels = nl;
			redraw();
			return;
		}
		if (moveState) {
			const p = getCanvasCoords(e);
			const dx = p.x - moveState.startMX;
			const dy = p.y - moveState.startMY;
			if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
				const nl = [...labels];
				nl[moveState.idx] = {
					...moveState.label,
					x: Math.round(moveState.label.x + dx),
					y: Math.round(moveState.label.y + dy)
				};
				labels = nl;
				redraw();
			}
			return;
		}
		if (isDrawing) {
			const p = getCanvasCoords(e);
			curX = p.x; curY = p.y;
			redraw();
			return;
		}
		const p = getCanvasCoords(e);
		hoverOverSelected = selectedIdx >= 0 && selectedIdx < labels.length
			&& p.x >= labels[selectedIdx].x && p.x <= labels[selectedIdx].x + labels[selectedIdx].width
			&& p.y >= labels[selectedIdx].y && p.y <= labels[selectedIdx].y + labels[selectedIdx].height;
		updateCursor();
	}

	function handleCanvasLeave() {
		hoverOverSelected = false;
		if (isPanning) { isPanning = false; updateCursor(); }
		if (isDrawing) { isDrawing = false; }
	}

	function handleMU() {
		hoverOverSelected = false;
		if (isPanning) { isPanning = false; updateCursor(); return; }
		if (moveState) { moveState = null; return; }
		if (!isDrawing) return;
		isDrawing = false;
		const x = Math.min(startX, curX), y = Math.min(startY, curY);
		const w = Math.abs(curX - startX), h = Math.abs(curY - startY);
		if (w < 4 || h < 4) return;
		labels = [...labels, { name: `sprite${labels.length + 1}`, x: Math.round(x), y: Math.round(y), width: Math.round(w), height: Math.round(h) }];
		selectedIdx = labels.length - 1;
		updateCursor();
		redraw();
	}

	function handleWheelPreventDefault(e: WheelEvent) {
		if (!hasImage) return;
		e.preventDefault();
	}

	$effect(() => {
		if (!canvasEl) return;
		const c = canvasEl.getContext('2d');
		if (!c) return;
		const off = document.createElement('canvas');
		off.width = 16; off.height = 16;
		const octx = off.getContext('2d')!;
		octx.fillStyle = '#2a2a2a';
		octx.fillRect(0, 0, 16, 16);
		octx.fillStyle = '#1a1a1a';
		octx.fillRect(0, 0, 8, 8);
		octx.fillRect(8, 8, 8, 8);
		checkerPattern = c.createPattern(off, 'repeat');
	});

	$effect(() => {
		if (!img || !canvasEl || !checkerPattern) return;
		canvasEl.width = img.naturalWidth;
		canvasEl.height = img.naturalHeight;
		ctx = canvasEl.getContext('2d');
		redraw();
	});

	let sidebarEl: HTMLDivElement = $state() as unknown as HTMLDivElement;
	let sortedIndices = $derived(labels.map((_, i) => i).sort((a, b) => labels[a].name.localeCompare(labels[b].name)));
	let prevImgSrc = '';

	function handleGlobalKey(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			if (isDrawing) { isDrawing = false; updateCursor(); }
			if (resizeState) { resizeState = null; }
			if (moveState) {
				const nl = [...labels];
				nl[moveState.idx] = { ...moveState.label };
				labels = nl;
				moveState = null;
				redraw();
			}
		}
	}

	$effect(() => {
		if (selectedIdx < 0 || !sidebarEl) return;
		const el = sidebarEl.querySelector(`[data-label-idx="${selectedIdx}"]`);
		el?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
	});

	$effect(() => {
		if (img && img.src !== prevImgSrc) {
			prevImgSrc = img.src;
			selectedIdx = -1; zoom = 1; panX = 0; panY = 0;
		}
	});

	function saveJSON() {
		if (labels.length === 0) return;
		const blob = new Blob([JSON.stringify(labels, null, 2)], { type: 'application/json' });
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url; a.download = 'sprites.json'; a.click();
		URL.revokeObjectURL(url);
	}

	function loadJSONFile(file: File) {
		const reader = new FileReader();
		reader.onload = () => {
			try {
				const data = JSON.parse(reader.result as string);
				if (!Array.isArray(data)) throw new Error('not an array');
				labels = data; selectedIdx = -1;
				if (img) redraw();
			} catch { alert('Invalid JSON: expected an array of sprite labels'); }
		};
		reader.readAsText(file);
	}

	function handleLoadJSON() {
		const inp = document.createElement('input');
		inp.type = 'file'; inp.accept = '.json,application/json';
		inp.onchange = () => { const f = inp.files?.[0]; if (f) loadJSONFile(f); };
		inp.click();
	}

	function getImageData(): { data: Uint8ClampedArray; w: number; h: number } | null {
		if (!img) return null;
		const c = document.createElement('canvas');
		c.width = img.naturalWidth; c.height = img.naturalHeight;
		const cx = c.getContext('2d')!;
		cx.drawImage(img, 0, 0);
		const d = cx.getImageData(0, 0, c.width, c.height);
		return { data: d.data, w: d.width, h: d.height };
	}

	function floodFillAt(sx: number, sy: number, threshold = 10): { x: number; y: number; width: number; height: number } | null {
		const id = getImageData();
		if (!id) return null;
		const { data, w, h } = id;
		const idx = sy * w + sx;
		if (sx < 0 || sx >= w || sy < 0 || sy >= h || data[idx * 4 + 3] <= threshold) return null;

		const visited = new Uint8Array(w * h);
		let x1 = sx, x2 = sx, y1 = sy, y2 = sy;
		const stack: [number, number][] = [[sx, sy]];
		visited[idx] = 1;

		while (stack.length) {
			const [cx, cy] = stack.pop()!;
			if (cx < x1) x1 = cx; if (cx > x2) x2 = cx;
			if (cy < y1) y1 = cy; if (cy > y2) y2 = cy;
			for (const [nx, ny] of [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]] as const) {
				if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
				const ni = ny * w + nx;
				if (visited[ni] || data[ni * 4 + 3] <= threshold) continue;
				visited[ni] = 1;
				stack.push([nx, ny]);
			}
		}

		const bw = x2 - x1 + 1, bh = y2 - y1 + 1;
		if (bw < 4 || bh < 4) return null;
		return { x: x1, y: y1, width: bw, height: bh };
	}

	function handleDblClick(e: MouseEvent) {
		if (!hasImage) return;
		const p = getCanvasCoords(e);
		const hit = hitTestLabel(p.x, p.y);
		if (hit >= 0) {
			labels = labels.filter((_, i) => i !== hit);
			if (selectedIdx === hit) selectedIdx = -1;
			else if (selectedIdx > hit) selectedIdx--;
		}
		const box = floodFillAt(Math.floor(p.x), Math.floor(p.y));
		if (box) {
			labels = [...labels, { name: `sprite${labels.length + 1}`, ...box }];
			selectedIdx = labels.length - 1;
		}
		redraw();
	}

	function autoDetect() {
		if (!img) return;
		const id = getImageData();
		if (!id) return;
		const { data, w, h } = id;
		const v = new Uint8Array(w * h);
		const threshold = 10;

		interface Box { x1: number; y1: number; x2: number; y2: number; }
		const boxes: Box[] = [];

		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const i = y * w + x;
				if (data[i * 4 + 3] <= threshold || v[i]) continue;
				let x1 = x, x2 = x, y1 = y, y2 = y;
				const stack: [number, number][] = [[x, y]];
				v[i] = 1;
				while (stack.length) {
					const [cx2, cy] = stack.pop()!;
					if (cx2 < x1) x1 = cx2; if (cx2 > x2) x2 = cx2;
					if (cy < y1) y1 = cy; if (cy > y2) y2 = cy;
					for (const [nx, ny] of [[cx2 - 1, cy], [cx2 + 1, cy], [cx2, cy - 1], [cx2, cy + 1]] as const) {
						if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
						const ni = ny * w + nx;
						if (v[ni] || data[ni * 4 + 3] <= threshold) continue;
						v[ni] = 1; stack.push([nx, ny]);
					}
				}
				const bw = x2 - x1 + 1, bh = y2 - y1 + 1;
				if (bw >= 4 && bh >= 4) boxes.push({ x1, y1, x2, y2 });
			}
		}

		boxes.sort((a, b) => a.y1 - b.y1 || a.x1 - b.x1);
		const rows: Box[][] = [];
		const rowH = boxes.length > 0 ? boxes.reduce((s, b) => s + (b.y2 - b.y1), 0) / boxes.length : 16;
		for (const b of boxes) {
			let placed = false;
			for (const r of rows) {
				if (Math.abs(b.y1 - r[0].y1) <= rowH * 0.5) { r.push(b); placed = true; break; }
			}
			if (!placed) rows.push([b]);
		}
		for (const r of rows) r.sort((a, b) => a.x1 - b.x1);
		const sorted = rows.flat();
		const pad = String(sorted.length).length;
		labels = sorted.map((b, i) => ({ name: `label ${String(i + 1).padStart(pad, '0')}`, x: b.x1, y: b.y1, width: b.x2 - b.x1 + 1, height: b.y2 - b.y1 + 1 }));
		selectedIdx = -1;
		redraw();
	}

	function removeLabel(idx: number) {
		labels = labels.filter((_, i) => i !== idx);
		if (selectedIdx === idx) selectedIdx = -1;
		else if (selectedIdx > idx) selectedIdx--;
		redraw();
	}

	function selectLabel(idx: number) { selectedIdx = idx; redraw(); }

	function startEdit(idx: number) { editIdx = idx; editNameVal = labels[idx].name; }

	function commitEdit() {
		if (editIdx >= 0 && editIdx < labels.length) {
			const nl = [...labels];
			nl[editIdx] = { ...nl[editIdx], name: editNameVal || `sprite${editIdx + 1}` };
			labels = nl;
		}
		editIdx = -1; editNameVal = ''; redraw();
	}

	function toggleLabelNames() { showLabelNames = !showLabelNames; redraw(); }

	function resetLabels() {
		labels = []; selectedIdx = -1; selectedSet = new Set();
		zoom = 1; panX = 0; panY = 0;
		redraw();
	}

	function mergeLabels() {
		if (selectedSet.size < 2) return;
		let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
		for (const i of selectedSet) {
			const l = labels[i];
			if (l.x < x1) x1 = l.x;
			if (l.y < y1) y1 = l.y;
			if (l.x + l.width > x2) x2 = l.x + l.width;
			if (l.y + l.height > y2) y2 = l.y + l.height;
		}
		const merged: SpriteLabel = {
			name: labels[[...selectedSet][0]].name,
			x: x1, y: y1, width: x2 - x1, height: y2 - y1
		};
		labels = [...labels.filter((_, i) => !selectedSet.has(i)), merged];
		selectedSet = new Set([labels.length - 1]);
		selectedIdx = labels.length - 1;
		redraw();
	}
</script>

<svelte:window onkeydown={handleGlobalKey} />

<div class="flex flex-col gap-4 h-full">
	<div class="flex items-center gap-2 flex-wrap">
		<button onclick={saveJSON} disabled={!hasImage || labels.length === 0}
			class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
			<span class="material-icons text-sm">save</span> Save JSON
		</button>
		<button onclick={handleLoadJSON} disabled={!hasImage}
			class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
			<span class="material-icons text-sm">upload_file</span> Load JSON
		</button>
		<button onclick={autoDetect} disabled={!hasImage}
			class="flex items-center gap-1 px-3 py-1.5 bg-blue-700 hover:bg-blue-600 rounded text-sm disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
			<span class="material-icons text-sm">auto_fix_high</span> Auto Detect
		</button>
		<button onclick={toggleLabelNames} disabled={!hasImage}
			class="flex items-center gap-1 px-3 py-1.5 rounded text-sm disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer {showLabelNames ? 'bg-green-700 hover:bg-green-600' : 'bg-neutral-700 hover:bg-neutral-600'}">
			<span class="material-icons text-sm">{showLabelNames ? 'label_off' : 'label'}</span> Names
		</button>
		<button onclick={() => { galleryView = !galleryView; }} disabled={!hasImage}
			class="flex items-center gap-1 px-3 py-1.5 rounded text-sm disabled:opacity-40 cursor-pointer {galleryView ? 'bg-green-700 hover:bg-green-600' : 'bg-neutral-700 hover:bg-neutral-600'}">
			<span class="material-icons text-sm">grid_view</span> Gallery
		</button>
		<button onclick={mergeLabels} disabled={selectedSet.size < 2}
			class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer">
			<span class="material-icons text-sm">merge_type</span> Merge
		</button>
		{#if hasImage}
			<span class="text-xs text-neutral-400 ml-2">{labels.length} region{labels.length !== 1 ? 's' : ''}</span>
			<span class="text-xs text-neutral-600">{Math.round(zoom * 100)}%</span>
			<button onclick={resetLabels}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">restart_alt</span> Reset
			</button>
		{/if}
	</div>

	{#if !galleryView}
		<div class="flex gap-4 flex-1 min-h-0">
			<div role="none" class="flex-1 overflow-hidden border border-neutral-700 rounded bg-neutral-900 relative select-none"
				onwheel={handleWheelPreventDefault}
				onmousedown={(e) => { if (e.button === 1) { e.preventDefault(); isPanning = true; isDrawing = false; panStartX = e.clientX - panX; panStartY = e.clientY - panY; updateCursor(); } }}
				onmousemove={(e) => { if (isPanning) { panX = e.clientX - panStartX; panY = e.clientY - panStartY; } }}
				onmouseup={() => { if (isPanning) { isPanning = false; updateCursor(); } }}
				onmouseleave={() => { if (isPanning) { isPanning = false; updateCursor(); } }}
			>
				{#if hasImage}
					<canvas
						bind:this={canvasEl}
						class="block"
						style="transform-origin:0 0;transform:translate({panX}px,{panY}px) scale({zoom});image-rendering:pixelated"
						style:cursor={canvasCursor}
						onwheel={handleWheel}
						onmousedown={handleMD}
						onmousemove={handleMM}
						onmouseup={handleMU}
						onmouseleave={handleCanvasLeave}
						ondblclick={handleDblClick}
						aria-label="Sprite canvas"
					></canvas>
					<div class="absolute inset-0 pointer-events-none">
						{#each labels as label, i}
							{@const sel = selectedSet.has(i)}
							<div
								class="absolute pointer-events-none box-border"
								style="left:{panX + label.x * zoom}px;top:{panY + label.y * zoom}px;width:{label.width * zoom}px;height:{label.height * zoom}px;
									border:{(sel ? 3 : 2)}px solid {sel ? '#22c55e' : '#ef4444'};
									background:{(sel ? 'rgba(34,197,94,0.12)' : 'rgba(239,68,68,0.08)')};"
							></div>
						{/each}
					</div>
					{#if selectedIdx >= 0 && selectedIdx < labels.length}
						{@const l = labels[selectedIdx]}
						<div class="absolute inset-0 pointer-events-none">
							{#each getHandles(l) as handle}
								<div
									class="absolute w-2.5 h-2.5 bg-white border-2 border-green-500 -translate-x-1/2 -translate-y-1/2 pointer-events-auto box-border"
									style="left:{panX + handle.x * zoom}px;top:{panY + handle.y * zoom}px;cursor:{cursorForHandle(handle.type)}"
									onmousedown={(e) => { e.stopPropagation(); resizeState = { idx: selectedIdx, handle: handle.type, startMX: handle.x, startMY: handle.y, label: { ...l } }; const h = (ev: MouseEvent) => { if (resizeState) resizeState = null; updateCursor(); document.removeEventListener('mouseup', h); }; document.addEventListener('mouseup', h); }}
									role="button" tabindex="-1"
								></div>
							{/each}
						</div>
					{/if}
				{:else}
					<div class="flex flex-col items-center justify-center h-full text-neutral-500 select-none py-16">
						<span class="material-icons text-5xl mb-2">image</span>
						<p class="text-sm">Open a spritesheet image to begin</p>
					</div>
				{/if}
			</div>

			{#if hasImage}
				<div bind:this={sidebarEl} class="w-56 shrink-0 flex flex-col gap-1 overflow-y-auto">
					<div class="text-xs text-neutral-400 font-semibold uppercase tracking-wider mb-1">Labels</div>
					{#if labels.length === 0}
						<p class="text-xs text-neutral-600">No labels yet.</p>
					{/if}
					{#each sortedIndices as i (labels[i])}
						<div
							data-label-idx={i}
							class="flex items-center gap-1 px-2 py-1 rounded text-xs {selectedSet.has(i) ? 'bg-neutral-700 ring-1 ring-green-500' : 'bg-neutral-800 hover:bg-neutral-750'} cursor-pointer group"
							onclick={(e) => { if (e.shiftKey) { const s = new Set(selectedSet); if (s.has(i)) s.delete(i); else s.add(i); selectedSet = s; selectedIdx = i; redraw(); } else { selectLabel(i); } }}
							role="button" tabindex="0"
							onkeydown={(e) => e.key === 'Enter' && selectLabel(i)}
						>
							<span class="material-icons text-xs text-red-400 shrink-0">crop_square</span>
							{#if editIdx === i}
								<input type="text" bind:value={editNameVal} onblur={commitEdit}
									onkeydown={(e) => { if (e.key === 'Enter' || e.key === 'Escape') commitEdit(); }}
									class="flex-1 bg-neutral-900 border border-neutral-600 rounded px-1 py-0.5 text-xs outline-none" use:autoFocus />
							{:else}
								<span class="flex-1 truncate" onclick={(e) => { e.stopPropagation(); selectLabel(i); startEdit(i); }} onkeydown={(e) => e.key === 'Enter' && (selectLabel(i), startEdit(i))} role="button" tabindex="-1">{labels[i].name}</span>
							{/if}
							<span class="text-neutral-500 shrink-0">{labels[i].width}&times;{labels[i].height}</span>
							<button onclick={() => removeLabel(i)} class="text-neutral-600 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity cursor-pointer" title="Delete">
								<span class="material-icons text-xs">close</span>
							</button>
						</div>
					{/each}
				</div>
			{/if}
		</div>
	{:else}
		<div class="flex-1 overflow-y-auto"
			onwheel={(e) => { if (labels.length > 0) { e.preventDefault(); const d = -e.deltaY * 0.001; galleryZoom = Math.max(0.25, Math.min(6, galleryZoom * (1 + d))); } }}
		>
			{#if labels.length === 0}
				<p class="text-xs text-neutral-500 text-center py-16">No labels yet.</p>
			{:else}
				<div class="flex flex-wrap gap-3 justify-center p-2">
					{#each sortedIndices as i (labels[i])}
						{@const label = labels[i]}
						{@const gw = 80 * galleryZoom}
						{@const gh = 96 * galleryZoom}
						{@const s = img ? Math.min(gw / label.width, gh / label.height) : 1}
						<div
							class="flex flex-col items-center gap-1.5 p-2 rounded cursor-pointer {selectedSet.has(i) ? 'bg-neutral-700 ring-2 ring-green-500' : 'bg-neutral-800 hover:bg-neutral-750'}"
							onclick={(e) => { if (e.shiftKey) { const ns = new Set(selectedSet); if (ns.has(i)) ns.delete(i); else ns.add(i); selectedSet = ns; selectedIdx = i; redraw(); } else { selectLabel(i); } }}
							role="button" tabindex="0"
							onkeydown={(e) => e.key === 'Enter' && selectLabel(i)}
						>
							<div class="relative bg-neutral-950 rounded border border-neutral-600 flex items-center justify-center overflow-hidden"
								style="width:{gw}px;height:{gh}px"
							>
								<button onclick={(e) => { e.stopPropagation(); removeLabel(i); }}
									class="absolute top-0.5 right-0.5 text-neutral-500 hover:text-red-400 cursor-pointer z-10" title="Delete">
									<span class="material-icons text-xs">close</span>
								</button>
								<div
									style="width:{label.width * s}px;height:{label.height * s}px;background-image:url({img?.src});background-repeat:no-repeat;background-position:{(-label.x * s).toFixed(0)}px {(-label.y * s).toFixed(0)}px;background-size:{(img?.naturalWidth ?? 1) * s}px {(img?.naturalHeight ?? 1) * s}px;"
								></div>
							</div>
							{#if editIdx === i}
								<input type="text" bind:value={editNameVal} onblur={commitEdit}
									onkeydown={(e) => { if (e.key === 'Enter' || e.key === 'Escape') commitEdit(); }}
									class="bg-neutral-900 border border-neutral-600 rounded px-1 py-0.5 text-xs outline-none text-center" use:autoFocus
									style="width:{gw}px"
								/>
							{:else}
								<span class="text-xs text-neutral-300 text-center truncate leading-tight" onclick={(e) => { e.stopPropagation(); selectLabel(i); startEdit(i); }} onkeydown={(e) => e.key === 'Enter' && (selectLabel(i), startEdit(i))} role="button" tabindex="-1" style="width:{gw}px">{label.name}</span>
							{/if}
							<span class="text-[10px] text-neutral-500">{label.width}&times;{label.height}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>
	{/if}
</div>