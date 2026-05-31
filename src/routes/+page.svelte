<script lang="ts">
	import type { SpriteLabel } from '$lib/types';
	import SpriteLabeler from '$lib/components/SpriteLabeler.svelte';
	import AnimationEditor from '$lib/components/AnimationEditor.svelte';
	import BackgroundRemover from '$lib/components/BackgroundRemover.svelte';

	let activeTab = $state('background');
	let img = $state<HTMLImageElement | null>(null);
	let labels: SpriteLabel[] = $state([]);
	let hasImage = $state(false);
	let fileInput: HTMLInputElement;

	function handleOpenImage() {
		if (!fileInput) return;
		fileInput.value = '';
		fileInput.click();
	}

	async function pasteFromClipboard() {
		try {
			const items = await navigator.clipboard.read();
			for (const item of items) {
				const blob = await item.getType('image/png').catch(() => null) || await item.getType('image/webp').catch(() => null);
				if (!blob) continue;
				const el = new Image();
				el.onload = () => { img = el; hasImage = true; labels = []; };
				el.src = URL.createObjectURL(blob);
				return;
			}
		} catch {}
	}

	function onFileSelected() {
		const f = fileInput.files?.[0];
		if (!f) return;
		const reader = new FileReader();
		reader.onload = () => {
			const el = new Image();
			el.onload = () => {
				img = el; hasImage = true; labels = [];
			};
			el.src = reader.result as string;
		};
		reader.readAsDataURL(f);
	}
</script>

<div class="h-dvh flex flex-col bg-neutral-900 text-white">
	<nav class="flex items-center gap-2 px-4 py-2 bg-neutral-800 border-b border-neutral-700 shrink-0">
		<button onclick={handleOpenImage}
			class="flex items-center gap-1.5 px-3 py-1.5 rounded text-sm bg-blue-700 hover:bg-blue-600 cursor-pointer transition-colors">
			{#if img}
				<img src={img.src} alt="" class="w-5 h-5 object-cover rounded" />
			{:else}
				<span class="material-icons text-sm">folder_open</span>
			{/if}
			Open Image
		</button>
		<button onclick={pasteFromClipboard}
			class="flex items-center gap-1.5 px-3 py-1.5 rounded text-sm bg-blue-700 hover:bg-blue-600 cursor-pointer transition-colors">
			<span class="material-icons text-sm">content_paste</span>
			From Clipboard
		</button>
		<span class="w-px h-5 bg-neutral-600"></span>
		<button
			onclick={() => activeTab = 'background'}
			class="flex items-center gap-1.5 px-3 py-1.5 rounded text-sm
				{activeTab === 'background' ? 'bg-neutral-700 text-white' : 'text-neutral-400 hover:text-white hover:bg-neutral-750'}
				cursor-pointer transition-colors"
		>
			<span class="material-icons text-sm">auto_fix_high</span>
			Background Removal
		</button>
		<button
			onclick={() => activeTab = 'labeler'}
			class="flex items-center gap-1.5 px-3 py-1.5 rounded text-sm
				{activeTab === 'labeler' ? 'bg-neutral-700 text-white' : 'text-neutral-400 hover:text-white hover:bg-neutral-750'}
				cursor-pointer transition-colors"
		>
			<span class="material-icons text-sm">crop</span>
			Sprite Labeler
		</button>
		<button
			onclick={() => activeTab = 'animation'}
			class="flex items-center gap-1.5 px-3 py-1.5 rounded text-sm
				{activeTab === 'animation' ? 'bg-neutral-700 text-white' : 'text-neutral-400 hover:text-white hover:bg-neutral-750'}
				cursor-pointer transition-colors"
		>
			<span class="material-icons text-sm">play_circle</span>
			Animation
		</button>
		<span class="ml-auto text-xs text-neutral-600">sprite-tools</span>
	</nav>

	<main class="flex-1 p-4 min-h-0 overflow-hidden">
		<div class="h-full {activeTab !== 'background' ? 'hidden' : ''}">
			<BackgroundRemover bind:img bind:labels bind:hasImage />
		</div>
		<div class="h-full {activeTab !== 'labeler' ? 'hidden' : ''}">
			<SpriteLabeler bind:img bind:labels bind:hasImage />
		</div>
		<div class="h-full {activeTab !== 'animation' ? 'hidden' : ''}">
			<AnimationEditor bind:img bind:labels bind:hasImage />
		</div>
	</main>

	<input type="file" accept="image/*" bind:this={fileInput} onchange={onFileSelected} class="hidden" />
</div>