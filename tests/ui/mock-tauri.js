// Injected into the page before the app loads. Fakes Tauri's IPC so the Svelte UI can run
// in a plain browser: every command is recorded in window.__calls, and window.__emit(event,
// payload) delivers backend events to the app's listeners.
//
// window.__MOCK_TRACK_COUNT (set before this script) switches to a large generated library.
(() => {
  const mk = (id, o) => ({
    id, path: `${o.dir}/${o.filename}`, title: null, artist: null, album_artist: null, album: null,
    genre: null, composer: null, comment: null, year: null, track: null, track_total: null, disc: null,
    disc_total: null, has_art: false, duration_ms: 200000, bitrate: 320, size: 5e6, error: null, ...o,
  });
  const count = window.__MOCK_TRACK_COUNT;
  const tracks = count
    ? Array.from({ length: count }, (_, i) =>
        mk(i + 1, { dir: `D${i % 300}`, filename: `${i}.mp3`, title: `T${i}`, artist: `A${i % 40}`, album: `Al${i % 300}`, track: i % 15 }))
    : [
        mk(1, { dir: 'X', filename: '1.mp3', title: 'One', artist: 'Alpha', album: 'Same', year: 2001, track: 1, has_art: true }),
        mk(2, { dir: 'X', filename: '2.mp3', title: 'Two', artist: 'Beta', album: 'Same', year: 2001, track: 2, composer: 'C' }),
        mk(3, { dir: 'Y', filename: '3.mp3', title: 'Three', artist: 'Gamma', album: 'Same', year: 2001, track: 3 }),
      ];

  window.__calls = [];
  window.__listeners = {};
  window.__emit = (event, payload) =>
    (window.__listeners[event] || []).forEach((h) => window['_' + h]({ event, payload, id: 0 }));

  let nextCallback = 0;
  window.__TAURI_INTERNALS__ = {
    metadata: { currentWindow: { label: 'main' }, currentWebview: { label: 'main', windowLabel: 'main' } },
    transformCallback: (f) => {
      const id = ++nextCallback;
      window['_' + id] = f;
      return id;
    },
    unregisterCallback: () => {},
    convertFileSrc: (p) => p,
    invoke: async (cmd, args) => {
      // Raw byte bodies (e.g. stage_image) are recorded by size.
      window.__calls.push([cmd, args instanceof Uint8Array ? { bytes: args.length } : JSON.parse(JSON.stringify(args ?? {}))]);
      switch (cmd) {
        case 'get_config':
          return { library_path: '/music', templates: ['<AlbumArtist>/<Album>/<Track:2> <Title>'] };
        case 'status':
          return { library_path: '/music', scanning: false, count: tracks.length };
        case 'query_tracks': {
          const q = args.query.search.toLowerCase();
          return q ? tracks.filter((t) => [t.title, t.artist, t.album, t.path].some((v) => v?.toLowerCase().includes(q))) : tracks;
        }
        case 'get_tracks':
          return tracks.filter((t) => args.ids.includes(t.id));
        case 'distinct_values':
          return ['Alpha', 'Beta'];
        case 'get_art':
          return null;
        case 'write_tags': {
          // window.__MOCK_WRITE_FAIL: ids whose writes fail.
          const fail = window.__MOCK_WRITE_FAIL || [];
          const failed = args.ids
            .filter((id) => fail.includes(id))
            .map((id) => ({ id, path: tracks.find((t) => t.id === id).path, message: 'Permission denied (os error 13)' }));
          return { updated: args.ids.length - failed.length, failed };
        }
        case 'show_in_folder':
          return null;
        case 'stage_image':
          return '/tmp/pasted-1.png';
        case 'image_preview':
          return 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
        case 'template_tokens':
          return [{ token: 'Artist', description: 'a' }, { token: 'Title', description: 't' }];
        case 'preview_reorganize':
          // The third file collides with the first to exercise conflict display.
          return tracks.filter((t) => args.ids.includes(t.id)).map((t, i) => ({
            id: t.id,
            from: t.path,
            to: i === 2 ? 'Alpha/Same/01 One.mp3' : `${t.artist}/${t.album}/0${t.track} ${t.title}.mp3`,
            status: i === 2 ? 'conflict' : 'move',
            message: i === 2 ? 'another selected file would get this path' : null,
          }));
        case 'plugin:event|listen':
          (window.__listeners[args.event] ||= []).push(args.handler);
          return args.handler;
        default:
          return null;
      }
    },
  };
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener: () => {} };
})();
