let d = '';
process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const j = JSON.parse(d);
    const p = (j.tool_input && j.tool_input.file_path) || '';
    if (p.endsWith('.dart')) {
      require('child_process').spawnSync(
        'powershell.exe',
        ['-NoProfile', '-Command', `& C:\\flutter\\bin\\dart.bat format "${p}"`],
        { stdio: 'ignore' }
      );
    }
  } catch (e) {}
});
