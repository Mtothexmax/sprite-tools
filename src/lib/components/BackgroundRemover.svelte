<script lang="ts">
	let { img = $bindable(null), hasImage = $bindable(false), labels = $bindable([]) } = $props();

	let canvas: HTMLCanvasElement = $state() as unknown as HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = $state(null);
	let fillActive = $state(false);
	let fillConnected = $state(true);
	let fillTolerance = $state(20);
	let canvasCursor = $state('default');
	let canUndo = $state(false);
	let canRedo = $state(false);
	let zoom = $state(1);
	let panX = $state(0), panY = $state(0);
	let isPanning = $state(false);
	let panStartX = 0, panStartY = 0;
	let showFeatherDlg = $state(false);
	let featherRadius = $state(1);
	let featherSnapshot: ImageData | null = null;
	let showShrinkDlg = $state(false);
	let shrinkRadius = $state(1);
	let shrinkSnapshot: ImageData | null = null;
	let shrinkColorGuided = $state(false);
	let shrinkColorTol = $state(20);
	let pickedColor: [number, number, number] | null = $state(null);
	let colorPicking = $state(false);
	let hexInput = $state('');
	let lassoActive = $state(false);
	let lassoPoints: { x: number; y: number }[] = $state([]);
	let lassoPrev: { x: number; y: number } | null = $state(null);
	let rectActive = $state(false);
	let rectDragging = $state(false);
	let rectStart: { x: number; y: number } | null = $state(null);
	let rectEnd: { x: number; y: number } | null = $state(null);
	let toolSnapshot: ImageData | null = $state(null);

	const MAX_UNDO = 20;
	let undoStack: ImageData[] = [];
	let redoStack: ImageData[] = [];

	function saveState() {
		if (!ctx || !canvas) return;
		undoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		if (undoStack.length > MAX_UNDO) undoStack.shift();
		redoStack = [];
		canUndo = undoStack.length > 0;
		canRedo = false;
	}

	function restoreState(data: ImageData) {
		if (!ctx) return;
		canvas.width = data.width;
		canvas.height = data.height;
		ctx.putImageData(data, 0, 0);
	}

	function undo() {
		if (undoStack.length === 0 || !ctx || !canvas) return;
		redoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		const data = undoStack.pop()!;
		restoreState(data);
		canUndo = undoStack.length > 0;
		canRedo = true;
	}

	function redo() {
		if (redoStack.length === 0 || !ctx || !canvas) return;
		undoStack.push(ctx.getImageData(0, 0, canvas.width, canvas.height));
		const data = redoStack.pop()!;
		restoreState(data);
		canUndo = true;
		canRedo = redoStack.length > 0;
	}

	function resetImage() {
		if (!img || !canvas) return;
		canvas.width = img.naturalWidth;
		canvas.height = img.naturalHeight;
		ctx = canvas.getContext('2d', { willReadFrequently: true })!;
		ctx.drawImage(img, 0, 0);
		fillActive = false; lassoActive = false; lassoPoints = []; lassoPrev = null;
		rectActive = false; rectDragging = false; rectStart = null; rectEnd = null;
		canvasCursor = 'default';
		undoStack = []; redoStack = [];
		canUndo = false; canRedo = false;
		zoom = 1; panX = 0; panY = 0;
	}

	$effect(() => {
		if (img && canvas) { resetImage(); saveState(); }
	});

	function getCanvasCoords(e: MouseEvent): { x: number; y: number } {
		const r = canvas.getBoundingClientRect();
		return {
			x: (e.clientX - r.left) * (canvas.width / r.width),
			y: (e.clientY - r.top) * (canvas.height / r.height)
		};
	}

	function getPixel(e: MouseEvent): { x: number; y: number; idx: number } | null {
		if (!ctx || !canvas) return null;
		const p = getCanvasCoords(e);
		const x = Math.floor(p.x), y = Math.floor(p.y);
		if (x < 0 || x >= canvas.width || y < 0 || y >= canvas.height) return null;
		return { x, y, idx: (y * canvas.width + x) * 4 };
	}

	function applyOp(fn: () => void) {
		saveState();
		fn();
	}

	function handleWheel(e: WheelEvent) {
		e.preventDefault();
		const r = canvas.getBoundingClientRect();
		const mx = e.clientX - r.left, my = e.clientY - r.top;
		const cx = mx / r.width * canvas.width;
		const cy = my / r.height * canvas.height;
		const delta = -e.deltaY * 0.001;
		const nz = Math.max(0.1, Math.min(20, zoom * (1 + delta)));
		panX = cx * zoom + panX - cx * nz;
		panY = cy * zoom + panY - cy * nz;
		zoom = nz;
	}

	function handleCanvasClick(e: MouseEvent) {
		if (lassoActive) { lassoClick(e); return; }
		const p = getPixel(e);
		if (!p || !ctx) return;
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		if (fillActive) {
			const [pr, pg, pb] = [data.data[p.idx], data.data[p.idx + 1], data.data[p.idx + 2]];
			const cx = p.x, cy = p.y;
			applyOp(() => fillToTransparent(pr, pg, pb, cx, cy, data));
		} else if (colorPicking) {
			const [r, g, b] = [data.data[p.idx], data.data[p.idx + 1], data.data[p.idx + 2]];
			pickedColor = [r, g, b];
			hexInput = '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
			colorPicking = false;
		}
	}

	function fillToTransparent(pr: number, pg: number, pb: number, cx: number, cy: number, data: ImageData) {
		const d = data.data;
		const w = data.width, h = data.height;
		const maxDelta = fillTolerance * 2.55;
		const targetMax = Math.max(pr, pg, pb);
		const targetMin = Math.min(pr, pg, pb);
		const targetChroma = targetMax - targetMin;
		const match = (idx: number) => {
			const r = d[idx], g = d[idx + 1], b = d[idx + 2];
			if (Math.abs(r - pr) > maxDelta) return false;
			if (Math.abs(g - pg) > maxDelta) return false;
			if (Math.abs(b - pb) > maxDelta) return false;
			const currentMax = Math.max(r, g, b);
			const currentMin = Math.min(r, g, b);
			const currentChroma = currentMax - currentMin;
			if (Math.abs(targetChroma - currentChroma) > maxDelta) return false;
			return true;
		};
		if (!fillConnected) {
			for (let i = 0; i < d.length; i += 4) {
				if (match(i)) d[i + 3] = 0;
			}
		} else {
			const visited = new Uint8Array(w * h);
			const stack: [number, number][] = [[cx, cy]];
			if (!match((cy * w + cx) * 4)) return;

			function scanLine(lx: number, rx: number, sy: number) {
				let added = false;
				for (let i = lx; i <= rx; i++) {
					const idx = sy * w + i;
					if (visited[idx]) { added = false; continue; }
					if (match(idx * 4)) { if (!added) { stack.push([i, sy]); added = true; } }
					else { added = false; }
				}
				let li = lx - 1;
				while (li >= 0 && !visited[sy * w + li] && match((sy * w + li) * 4)) { li--; }
				if (li + 1 < lx) { const p = li + 1; if (!visited[sy * w + p]) stack.push([p, sy]); }
				let ri = rx + 1;
				while (ri < w && !visited[sy * w + ri] && match((sy * w + ri) * 4)) { ri++; }
				if (ri - 1 > rx) { const p = rx + 1; if (!visited[sy * w + p]) stack.push([p, sy]); }
			}

			while (stack.length) {
				const [sx, sy2] = stack.pop()!;
				let lx = sx;
				while (lx >= 0) {
					if (visited[sy2 * w + lx] || !match((sy2 * w + lx) * 4)) break;
					lx--;
				}
				lx++;
				let rx = sx;
				while (rx < w) {
					if (visited[sy2 * w + rx] || !match((sy2 * w + rx) * 4)) break;
					rx++;
				}
				rx--;
				for (let i = lx; i <= rx; i++) { visited[sy2 * w + i] = 1; d[(sy2 * w + i) * 4 + 3] = 0; }
				if (sy2 > 0) scanLine(lx, rx, sy2 - 1);
				if (sy2 < h - 1) scanLine(lx, rx, sy2 + 1);
			}
		}
		ctx!.putImageData(data, 0, 0);
	}

	function startFill() {
		fillActive = true; lassoActive = false; lassoPoints = []; lassoPrev = null; clearLasso();
		rectActive = false; rectDragging = false; rectStart = null; rectEnd = null; updateCursor();
	}

	function startColorPick() {
		if (colorPicking) { colorPicking = false; return; }
		fillActive = false; lassoActive = false; lassoPoints = []; lassoPrev = null; clearLasso();
		rectActive = false; rectDragging = false; rectStart = null; rectEnd = null;
		colorPicking = true;
	}

	function startLasso() {
		if (lassoActive) { lassoActive = false; lassoPoints = []; lassoPrev = null; clearLasso(); updateCursor(); return; }
		lassoActive = true; lassoPoints = []; lassoPrev = null; takeSnapshot();
		fillActive = false; colorPicking = false; rectActive = false; rectDragging = false; rectStart = null; rectEnd = null; updateCursor();
	}

	function startRect() {
		if (rectActive) { rectActive = false; rectDragging = false; rectStart = null; rectEnd = null; clearLasso(); updateCursor(); return; }
		rectActive = true; rectDragging = false; rectStart = null; rectEnd = null; takeSnapshot();
		lassoActive = false; lassoPoints = []; lassoPrev = null; fillActive = false; colorPicking = false; clearLasso(); updateCursor();
	}

	function updateCursor() {
		if (isPanning) { canvasCursor = 'grabbing'; return; }
		if (fillActive || colorPicking || lassoActive || rectActive) { canvasCursor = 'crosshair'; return; }
		canvasCursor = 'default';
	}

	function handleMD(e: MouseEvent) {
		if (!hasImage || !canvas) return;
		if (e.button === 1) {
			e.preventDefault();
			isPanning = true;
			panStartX = e.clientX - panX;
			panStartY = e.clientY - panY;
			updateCursor();
			return;
		}
		if (rectActive) { rectMD(e); return; }
	}

	function handleMM(e: MouseEvent) {
		if (isPanning) {
			panX = e.clientX - panStartX;
			panY = e.clientY - panStartY;
			return;
		}
		if (lassoActive) { lassoMove(e); return; }
	}

	function handleMU() {
		if (isPanning) { isPanning = false; updateCursor(); }
	}

	function clearLasso() {
		if (ctx && canvas && toolSnapshot) ctx.putImageData(toolSnapshot, 0, 0);
	}

	function takeSnapshot() {
		if (!ctx || !canvas) return;
		toolSnapshot = ctx.getImageData(0, 0, canvas.width, canvas.height);
	}

	function drawLasso() {
		if (!ctx || !canvas || lassoPoints.length === 0) return;
		clearLasso();
		ctx.save();
		ctx.strokeStyle = '#22c55e';
		ctx.lineWidth = 3 / zoom;
		ctx.setLineDash([6 / zoom, 4 / zoom]);
		ctx.beginPath();
		ctx.moveTo(lassoPoints[0].x, lassoPoints[0].y);
		for (let i = 1; i < lassoPoints.length; i++) ctx.lineTo(lassoPoints[i].x, lassoPoints[i].y);
		if (lassoPrev) ctx.lineTo(lassoPrev.x, lassoPrev.y);
		ctx.stroke();
		ctx.setLineDash([]);
		for (const p of lassoPoints) { ctx.beginPath(); ctx.arc(p.x, p.y, 4 / zoom, 0, Math.PI * 2); ctx.fillStyle = '#22c55e'; ctx.fill(); }
		ctx.restore();
	}

	function lassoClick(e: MouseEvent) {
		if (!lassoActive || !ctx || !canvas) return;
		const p = getCanvasCoords(e);
		const cx = Math.round(p.x), cy = Math.round(p.y);
		if (lassoPoints.length > 2) {
			const dx = cx - lassoPoints[0].x, dy = cy - lassoPoints[0].y;
			if (Math.sqrt(dx * dx + dy * dy) < 10 / zoom) { closeLasso(); return; }
		}
		lassoPoints = [...lassoPoints, { x: cx, y: cy }];
		drawLasso();
	}

	function lassoMove(e: MouseEvent) {
		if (!lassoActive || !ctx || !canvas || lassoPoints.length === 0) return;
		const p = getCanvasCoords(e);
		lassoPrev = { x: Math.round(p.x), y: Math.round(p.y) };
		drawLasso();
	}

	function closeLasso() {
		if (!lassoActive || !ctx || !canvas || lassoPoints.length < 3) { lassoPoints = []; lassoPrev = null; clearLasso(); return; }
		clearLasso();
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		applyOp(() => {
			const d = data.data, w = canvas!.width, h = canvas!.height;
			const pts = lassoPoints.map(p => [p.x, p.y]);
			for (let y = 0; y < h; y++) {
				for (let x = 0; x < w; x++) {
					let inside = false;
					for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
						const [xi, yi] = pts[i], [xj, yj] = pts[j];
						if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
					}
					if (inside) d[(y * w + x) * 4 + 3] = 0;
				}
			}
			ctx!.putImageData(data, 0, 0);
		});
		lassoPoints = []; lassoPrev = null; takeSnapshot();
	}

	$effect(() => {
		if (!lassoActive) return;
		const onMove = (e: MouseEvent) => { if (lassoActive) lassoMove(e); };
		const onDown = (e: MouseEvent) => {
			if (!lassoActive || !ctx || !canvas) return;
			if (e.button !== 0) return;
			if (e.target === canvas) return;
			const c = canvas.parentElement;
			if (!c || !c.contains(e.target as Node)) return;
			lassoClick(e);
		};
		document.addEventListener('mousemove', onMove);
		document.addEventListener('mousedown', onDown);
		return () => {
			document.removeEventListener('mousemove', onMove);
			document.removeEventListener('mousedown', onDown);
		};
	});

	let rectDocMove: ((e: MouseEvent) => void) | null = null;
	let rectDocUp: (() => void) | null = null;

	function rectMM(e: MouseEvent) {
		if (!rectActive || !rectDragging || !ctx || !canvas || !rectStart) return;
		const pt = getCanvasCoords(e);
		rectEnd = { x: Math.round(pt.x), y: Math.round(pt.y) };
		clearLasso();
		if (!ctx || !canvas) return;
		ctx.save();
		const x = Math.min(rectStart.x, rectEnd!.x), y = Math.min(rectStart.y, rectEnd!.y);
		const w2 = Math.abs(rectEnd!.x - rectStart.x), h2 = Math.abs(rectEnd!.y - rectStart.y);
		ctx.strokeStyle = '#22c55e'; ctx.lineWidth = 3 / zoom; ctx.setLineDash([6 / zoom, 4 / zoom]);
		ctx.strokeRect(x, y, w2, h2); ctx.setLineDash([]);
		ctx.restore();
	}

	function rectFinish() {
		if (!rectActive || !rectDragging || !ctx || !canvas || !rectStart || !rectEnd) { rectDragging = false; return; }
		rectDragging = false;
		const x1 = Math.min(rectStart.x, rectEnd.x), y1 = Math.min(rectStart.y, rectEnd.y);
		const x2 = Math.max(rectStart.x, rectEnd.x), y2 = Math.max(rectStart.y, rectEnd.y);
		if (x2 - x1 < 2 || y2 - y1 < 2) { clearLasso(); return; }
		clearLasso();
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		applyOp(() => {
			const d = data.data, w = canvas!.width, h = canvas!.height;
			const cx1 = Math.max(0, x1), cy1 = Math.max(0, y1);
			const cx2 = Math.min(w - 1, x2), cy2 = Math.min(h - 1, y2);
			for (let y = cy1; y <= cy2; y++) {
				for (let x = cx1; x <= cx2; x++) {
					d[(y * w + x) * 4 + 3] = 0;
				}
			}
			ctx!.putImageData(data, 0, 0);
		});
		rectStart = null; rectEnd = null; takeSnapshot();
	}

	function rectMD(e: MouseEvent) {
		if (!rectActive || !ctx || !canvas) return;
		const p = getCanvasCoords(e);
		rectStart = { x: Math.round(p.x), y: Math.round(p.y) };
		rectEnd = { x: Math.round(p.x), y: Math.round(p.y) };
		rectDragging = true;
		rectDocMove = (ev: MouseEvent) => rectMM(ev);
		rectDocUp = () => { document.removeEventListener('mousemove', rectDocMove!); document.removeEventListener('mouseup', rectDocUp!); rectFinish(); };
		document.addEventListener('mousemove', rectDocMove);
		document.addEventListener('mouseup', rectDocUp);
	}

	function copyImage() {
		if (!canvas) return;
		canvas.toBlob(b => {
			if (!b) return;
			navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).catch(() => {});
		});
	}

	async function pasteImage() {
		if (!ctx || !canvas) return;
		try {
			const items = await navigator.clipboard.read();
			for (const item of items) {
				const blob = await item.getType('image/png').catch(() => null) || await item.getType('image/webp').catch(() => null);
				if (!blob) continue;
				const img2 = new Image();
				img2.onload = () => {
					applyOp(() => {
						canvas.width = img2.naturalWidth;
						canvas.height = img2.naturalHeight;
						ctx!.drawImage(img2, 0, 0);
					});
				};
				img2.src = URL.createObjectURL(blob);
				return;
			}
		} catch {}
	}

	function copyAlpha() {
		if (!ctx || !canvas) return;
		const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
		const d = data.data;
		for (let i = 0; i < d.length; i += 4) {
			d[i] = d[i + 3]; d[i + 1] = d[i + 3]; d[i + 2] = d[i + 3]; d[i + 3] = 255;
		}
		const c = document.createElement('canvas');
		c.width = canvas.width; c.height = canvas.height;
		c.getContext('2d')!.putImageData(data, 0, 0);
		c.toBlob(b => {
			if (!b) return;
			navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).catch(() => {});
		});
	}

	async function pasteAlpha() {
		if (!ctx || !canvas) return;
		try {
			const items = await navigator.clipboard.read();
			for (const item of items) {
				const blob = await item.getType('image/png').catch(() => null) || await item.getType('image/webp').catch(() => null);
				if (!blob) continue;
				const img2 = new Image();
				img2.onload = () => {
					applyOp(() => {
						const c = document.createElement('canvas');
						c.width = img2.naturalWidth; c.height = img2.naturalHeight;
						const cx = c.getContext('2d')!;
						cx.drawImage(img2, 0, 0);
						const src = cx.getImageData(0, 0, c.width, c.height);
						const dst = ctx!.getImageData(0, 0, canvas!.width, canvas!.height);
						const sw = Math.min(c.width, canvas!.width);
						const sh = Math.min(c.height, canvas!.height);
						for (let y = 0; y < sh; y++) {
							for (let x = 0; x < sw; x++) {
								const si = (y * c.width + x) * 4;
								const di = (y * canvas!.width + x) * 4;
								const a = 0.299 * src.data[si] + 0.587 * src.data[si + 1] + 0.114 * src.data[si + 2];
								dst.data[di + 3] = Math.round(a);
							}
						}
						ctx!.putImageData(dst, 0, 0);
					});
				};
				img2.src = URL.createObjectURL(blob);
				return;
			}
		} catch {}
	}

	function saveImage() {
		if (!canvas) return;
		const a = document.createElement('a');
		a.href = canvas.toDataURL('image/png');
		a.download = 'image.png';
		a.click();
	}

	function applyToEditors() {
		if (!canvas) return;
		const el = new Image();
		el.onload = () => { img = el; labels = []; };
		el.src = canvas.toDataURL('image/png');
	}

	// Feather
	function openFeatherDlg() {
		if (!ctx || !canvas) return;
		featherSnapshot = ctx.getImageData(0, 0, canvas.width, canvas.height);
		featherRadius = 1;
		showFeatherDlg = true;
		featherPreview();
	}

	function findOpaque(sd: Uint8ClampedArray, w: number, h: number, ox: number, oy: number, r: number): [number, number, number] | null {
		for (let rr = 1; rr <= r; rr++) {
			for (let dy = -rr; dy <= rr; dy++) {
				for (let dx = -rr; dx <= rr; dx++) {
					if (Math.abs(dx) !== rr && Math.abs(dy) !== rr) continue;
					const nx = ox + dx, ny = oy + dy;
					if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
					const ni = (ny * w + nx) * 4;
					if (sd[ni + 3] === 255) return [sd[ni], sd[ni + 1], sd[ni + 2]];
				}
			}
		}
		return null;
	}

	function featherPreview() {
		if (!ctx || !canvas || !featherSnapshot) return;
		const sd = featherSnapshot.data;
		const w = featherSnapshot.width, h = featherSnapshot.height;
		const r = featherRadius;
		if (r < 1) { ctx.putImageData(featherSnapshot, 0, 0); return; }
		const shifted = new Uint8ClampedArray(sd);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const ci = (y * w + x) * 4;
				if (sd[ci + 3] === 0) continue;
				let minA = 255;
				for (let dy = -r; dy <= r; dy++) {
					for (let dx = -r; dx <= r; dx++) {
						const nx = x + dx, ny = y + dy;
						if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
						const a = sd[(ny * w + nx) * 4 + 3];
						if (a < minA) minA = a;
					}
				}
				shifted[ci + 3] = minA;
			}
		}
		const sigma = Math.max(r / 2, 0.5);
		const kw: number[] = [];
		let ksum = 0;
		for (let i = -r; i <= r; i++) { const w2 = Math.exp(-(i * i) / (2 * sigma * sigma)); kw.push(w2); ksum += w2; }
		for (let i = 0; i < kw.length; i++) kw[i] /= ksum;
		const tmp = new Float64Array(w * h);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				let sum = 0, ws = 0;
				for (let kx = -r; kx <= r; kx++) {
					const px = x + kx;
					if (px < 0 || px >= w) continue;
					sum += shifted[(y * w + px) * 4 + 3] * kw[kx + r];
					ws += kw[kx + r];
				}
				tmp[y * w + x] = ws > 0 ? sum / ws : 0;
			}
		}
		const dst = new Uint8ClampedArray(sd);
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const ci = (y * w + x) * 4;
				const sA = shifted[ci + 3];
				let hasTrans = false, hasOpaque = false;
				for (let dy = -r; dy <= r && !(hasTrans && hasOpaque); dy++) {
					for (let dx = -r; dx <= r && !(hasTrans && hasOpaque); dx++) {
						const nx = x + dx, ny = y + dy;
						if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
						const a = shifted[(ny * w + nx) * 4 + 3];
						if (a === 0) hasTrans = true;
						if (a === 255) hasOpaque = true;
					}
				}
				if (!hasTrans && sA === 255) continue;
				if (!hasOpaque && sA === 0) { dst[ci + 3] = 0; continue; }
				let sum = 0, ws = 0;
				for (let ky = -r; ky <= r; ky++) {
					const py = y + ky;
					if (py < 0 || py >= h) continue;
					sum += tmp[py * w + x] * kw[ky + r];
					ws += kw[ky + r];
				}
				dst[ci + 3] = Math.min(255, Math.max(0, Math.round(ws > 0 ? sum / ws : 0)));
				const c = findOpaque(sd, w, h, x, y, r);
				if (c) { dst[ci] = c[0]; dst[ci + 1] = c[1]; dst[ci + 2] = c[2]; }
			}
		}
		ctx.putImageData(new ImageData(dst, w, h), 0, 0);
	}

	function commitFeather() {
		if (!ctx || !canvas || !featherSnapshot) return;
		saveState();
		featherSnapshot = null;
		showFeatherDlg = false;
	}

	function cancelFeather() {
		if (!ctx || !canvas || !featherSnapshot) return;
		ctx.putImageData(featherSnapshot, 0, 0);
		featherSnapshot = null;
		showFeatherDlg = false;
	}

	function openShrinkDlg() {
		if (!ctx || !canvas) return;
		shrinkSnapshot = ctx.getImageData(0, 0, canvas.width, canvas.height);
		shrinkRadius = 1; shrinkColorGuided = false; shrinkColorTol = 20;
		showShrinkDlg = true;
		shrinkPreview();
	}

	function shrinkPreview() {
		if (!ctx || !canvas || !shrinkSnapshot) return;
		const sd = shrinkSnapshot.data;
		const w = shrinkSnapshot.width, h = shrinkSnapshot.height;
		const r = shrinkRadius;
		if (r < 1) { ctx.putImageData(shrinkSnapshot, 0, 0); return; }
		const dst = new Uint8ClampedArray(sd);
		const maxDelta = shrinkColorTol * 2.55;
		for (let y = 0; y < h; y++) {
			for (let x = 0; x < w; x++) {
				const ci = (y * w + x) * 4;
				const origA = sd[ci + 3];
				if (origA === 0) continue;
				if (shrinkColorGuided && pickedColor) {
					const [kr, kg, kb] = pickedColor;
					const dr = Math.abs(sd[ci] - kr), dg = Math.abs(sd[ci + 1] - kg), db = Math.abs(sd[ci + 2] - kb);
					if (dr <= maxDelta && dg <= maxDelta && db <= maxDelta) {
						let minA = 255;
						for (let dy = -r; dy <= r; dy++) {
							for (let dx = -r; dx <= r; dx++) {
								const nx = x + dx, ny = y + dy;
								if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
								const a = sd[(ny * w + nx) * 4 + 3];
								if (a < minA) minA = a;
							}
						}
						dst[ci + 3] = minA;
					}
				} else if (!shrinkColorGuided) {
					let minA = 255;
					for (let dy = -r; dy <= r; dy++) {
						for (let dx = -r; dx <= r; dx++) {
							const nx = x + dx, ny = y + dy;
							if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
							const a = sd[(ny * w + nx) * 4 + 3];
							if (a < minA) minA = a;
						}
					}
					dst[ci + 3] = minA;
				}
			}
		}
		ctx.putImageData(new ImageData(dst, w, h), 0, 0);
	}

	function commitShrink() {
		if (!ctx || !canvas || !shrinkSnapshot) return;
		saveState();
		shrinkSnapshot = null;
		showShrinkDlg = false;
	}

	function cancelShrink() {
		if (!ctx || !canvas || !shrinkSnapshot) return;
		ctx.putImageData(shrinkSnapshot, 0, 0);
		shrinkSnapshot = null;
		showShrinkDlg = false;
	}

	function updateHex() {
		const h = hexInput.replace('#', '');
		if (h.length !== 6) return;
		const v = parseInt(h, 16);
		if (isNaN(v)) return;
		pickedColor = [(v >> 16) & 255, (v >> 8) & 255, v & 255];
	}
</script>

<div class="flex flex-col gap-4 h-full">
	{#if !hasImage}
		<div class="flex flex-col items-center justify-center h-full text-neutral-500 select-none py-16">
			<span class="material-icons text-5xl mb-2">image</span>
			<p class="text-sm">Open a spritesheet image to begin</p>
		</div>
	{:else}
		<div class="flex items-center gap-2 flex-wrap">
			<button onclick={saveImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">download</span>
				Save Image
			</button>
			<button onclick={copyImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">content_copy</span>
				Copy Image
			</button>
			<button onclick={pasteImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">content_paste</span>
				Paste Image
			</button>
			<button onclick={copyAlpha}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">opacity</span>
				Copy Alpha
			</button>
			<button onclick={pasteAlpha}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">invert_colors</span>
				Paste Alpha
			</button>
			<span class="w-px h-5 bg-neutral-600"></span>
			<button onclick={startFill}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer {fillActive ? 'bg-green-700 ring-2 ring-green-400' : 'bg-neutral-700 hover:bg-neutral-600'}">
				<span class="material-icons text-sm">format_paint</span>
				Fill
			</button>
			<button onclick={startLasso}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer {lassoActive ? 'bg-green-700 ring-2 ring-green-400' : 'bg-neutral-700 hover:bg-neutral-600'}">
				<span class="material-icons text-sm">gesture</span>
				Lasso
			</button>
			<button onclick={startRect}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer {rectActive ? 'bg-green-700 ring-2 ring-green-400' : 'bg-neutral-700 hover:bg-neutral-600'}">
				<span class="material-icons text-sm">crop_square</span>
				Rectangle
			</button>
			<label class="flex items-center gap-1 text-xs text-neutral-400 cursor-pointer select-none">
				<input type="checkbox" bind:checked={fillConnected}
					class="accent-blue-500 w-3 h-3" />
				Connected
			</label>
			<div class="flex items-center gap-2 text-xs text-neutral-400">
				<input type="range" min="0" max="100" bind:value={fillTolerance}
					class="w-36 accent-blue-500" />
				<span class="w-8 text-right font-mono text-neutral-300">{fillTolerance}%</span>
			</div>
			<span class="w-px h-5 bg-neutral-600"></span>
			<button onclick={openFeatherDlg}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">blur_on</span>
				Feather
			</button>
			<button onclick={openShrinkDlg}
				class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">compress</span>
				Shrink
			</button>
			<button onclick={startColorPick}
				class="flex items-center gap-1 px-3 py-1.5 rounded text-sm cursor-pointer {colorPicking ? 'bg-green-700 ring-2 ring-green-400' : 'bg-neutral-700 hover:bg-neutral-600'}">
				<span class="material-icons text-sm">colorize</span>
				Pick Color
			</button>
			{#if pickedColor}
				<div class="w-5 h-5 rounded border border-neutral-500 shrink-0" style="background-color:rgb({pickedColor[0]},{pickedColor[1]},{pickedColor[2]})"></div>
				<input type="text" value={hexInput} oninput={(e) => { hexInput = (e.target as HTMLInputElement).value; updateHex(); }}
					class="w-20 bg-neutral-800 border border-neutral-700 rounded text-xs px-2 py-1 outline-none font-mono"
					placeholder="#FF00FF" />
			{/if}
			{#if zoom !== 1}
				<span class="text-xs text-neutral-600">{Math.round(zoom * 100)}%</span>
			{/if}
			<button onclick={applyToEditors} disabled={!hasImage}
				class="flex items-center gap-1 px-3 py-1.5 bg-blue-700 hover:bg-blue-600 rounded text-sm cursor-pointer">
				<span class="material-icons text-sm">send</span>
				Apply
			</button>
			<div class="ml-auto flex items-center gap-1">
				<button onclick={undo} disabled={!canUndo}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-30 cursor-pointer disabled:cursor-not-allowed">
					<span class="material-icons text-sm">undo</span>
				</button>
				<button onclick={redo} disabled={!canRedo}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm disabled:opacity-30 cursor-pointer disabled:cursor-not-allowed">
					<span class="material-icons text-sm">redo</span>
				</button>
				<button onclick={resetImage}
					class="flex items-center gap-1 px-3 py-1.5 bg-neutral-700 hover:bg-neutral-600 rounded text-sm cursor-pointer">
					<span class="material-icons text-sm">restart_alt</span>
					Reset
				</button>
			</div>
		</div>
		<div role="none" class="flex-1 overflow-hidden border border-neutral-700 rounded relative select-none"
			style="background-color:#1a1a1a;background-image:linear-gradient(45deg,#2a2a2a 25%,transparent 25%,transparent 75%,#2a2a2a 75%),linear-gradient(45deg,#2a2a2a 25%,transparent 25%,transparent 75%,#2a2a2a 75%);background-size:16px 16px;background-position:0 0,8px 8px;"
			onwheel={(e) => { if (hasImage) e.preventDefault(); }}
			onmousedown={handleMD}
			onmousemove={handleMM}
			onmouseup={handleMU}
			onmouseleave={() => { if (isPanning) { isPanning = false; updateCursor(); } }}
		>
			<canvas bind:this={canvas}
				class="block"
				style="transform-origin:0 0;transform:translate({panX}px,{panY}px) scale({zoom});image-rendering:pixelated;cursor:{canvasCursor}"
				onwheel={handleWheel}
				onclick={handleCanvasClick}
				onmousedown={(e) => { e.stopPropagation(); handleMD(e); }}
				onmousemove={(e) => { e.stopPropagation(); handleMM(e); }}
				onmouseup={(e) => { e.stopPropagation(); handleMU(e); }}
				onmouseleave={(e) => { e.stopPropagation(); handleMU(e); }}
				ondblclick={() => { if (lassoActive) closeLasso(); }}
				aria-label="Background removal canvas"
			></canvas>
		</div>
	{/if}
</div>

{#if showFeatherDlg}
	<div role="presentation" class="fixed inset-0 z-50 flex items-start justify-center pt-12" onclick={cancelFeather} onkeydown={(e) => e.key === 'Escape' && cancelFeather()}>
		<div role="presentation" onclick={(e) => e.stopPropagation()}
			class="bg-neutral-800 border border-neutral-700 rounded-lg shadow-xl p-5 flex flex-col gap-4 w-72"
		>
			<div class="flex items-center justify-between">
				<span class="text-sm font-semibold text-white">Feather</span>
				<button onclick={cancelFeather} class="text-neutral-500 hover:text-white cursor-pointer">
					<span class="material-icons text-sm">close</span>
				</button>
			</div>
			<div class="flex flex-col gap-3">
				<div>
					<div class="flex items-center justify-between text-xs text-neutral-300 mb-1">
						<span>Inward</span>
						<span class="text-sm font-mono text-white">{featherRadius}px</span>
					</div>
					<input type="range" min="0" max="10" value={featherRadius}
						oninput={(e) => { featherRadius = parseInt((e.target as HTMLInputElement).value); featherPreview(); }}
						class="w-full accent-blue-500" />
				</div>
			</div>
			<div class="flex justify-end gap-2">
				<button onclick={cancelFeather}
					class="px-3 py-1.5 rounded text-xs bg-neutral-700 hover:bg-neutral-600 cursor-pointer text-white">
					Cancel
				</button>
				<button onclick={commitFeather}
					class="px-3 py-1.5 rounded text-xs bg-blue-700 hover:bg-blue-600 cursor-pointer text-white">
					OK
				</button>
			</div>
		</div>
	</div>
{/if}

{#if showShrinkDlg}
	<div role="presentation" class="fixed inset-0 z-40" style="background-color:rgba(0,0,0,0.3);pointer-events:auto" onclick={() => cancelShrink()} onkeydown={(e) => e.key === 'Escape' && cancelShrink()}></div>
	<div role="presentation" class="fixed inset-0 z-50 flex items-start justify-center pt-12 pointer-events-none">
		<div role="presentation" onclick={(e) => e.stopPropagation()}
			class="pointer-events-auto bg-neutral-800 border border-neutral-700 rounded-lg shadow-xl p-5 flex flex-col gap-4 w-72"
		>
			<div class="flex items-center justify-between">
				<span class="text-sm font-semibold text-white">Shrink Inward</span>
				<button onclick={cancelShrink} class="text-neutral-500 hover:text-white cursor-pointer">
					<span class="material-icons text-sm">close</span>
				</button>
			</div>
			<div class="flex flex-col gap-3">
				<div>
					<div class="flex items-center justify-between text-xs text-neutral-300 mb-1">
						<span>Radius</span>
						<span class="text-sm font-mono text-white">{shrinkRadius}px</span>
					</div>
					<input type="range" min="0" max="10" value={shrinkRadius}
						oninput={(e) => { shrinkRadius = parseInt((e.target as HTMLInputElement).value); shrinkPreview(); }}
						class="w-full accent-blue-500" />
				</div>
				<label class="flex items-center gap-2 text-xs text-neutral-300 cursor-pointer select-none">
					<input type="checkbox" bind:checked={shrinkColorGuided}
						onchange={() => shrinkPreview()}
						class="accent-blue-500 w-3 h-3" />
					Color-guided{pickedColor ? ' (' + hexInput + ')' : ''}
				</label>
				{#if shrinkColorGuided && pickedColor}
					<div>
						<div class="flex items-center justify-between text-xs text-neutral-400 mb-1">
							<span>Color tolerance</span>
							<span class="text-sm font-mono text-neutral-300">{shrinkColorTol}%</span>
						</div>
						<input type="range" min="0" max="100" value={shrinkColorTol}
							oninput={(e) => { shrinkColorTol = parseInt((e.target as HTMLInputElement).value); shrinkPreview(); }}
							class="w-full accent-blue-500" />
					</div>
				{/if}
			</div>
			<div class="flex justify-end gap-2">
				<button onclick={cancelShrink}
					class="px-3 py-1.5 rounded text-xs bg-neutral-700 hover:bg-neutral-600 cursor-pointer text-white">
					Cancel
				</button>
				<button onclick={commitShrink}
					class="px-3 py-1.5 rounded text-xs bg-blue-700 hover:bg-blue-600 cursor-pointer text-white">
					OK
				</button>
			</div>
		</div>
	</div>
{/if}