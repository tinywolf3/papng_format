import { defineConfig, type Plugin } from 'vite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

const root = fileURLToPath(new URL('../../../',import.meta.url));
const samples = resolve(root,'samples');
function sampleAssets(): Plugin {
  return {
    name:'papng-samples',
    configureServer(server) {
      server.middlewares.use('/samples',(req,res,next) => {
        const name = (req.url ?? '').split('?')[0].replace(/^\//,'');
        if (!/^[a-z0-9-]+\.(papng|json)$/.test(name)) return next();
        try { res.setHeader('Content-Type',name.endsWith('.json')?'application/json':'application/octet-stream'); res.end(readFileSync(resolve(samples,name))); }
        catch { res.statusCode = 404; res.end('Sample not found'); }
      });
    },
    generateBundle() {
      for (const name of readdirSync(samples)) if (/\.(papng|json)$/.test(name)) this.emitFile({type:'asset',fileName:`samples/${name}`,source:readFileSync(resolve(samples,name))});
    }
  };
}
export default defineConfig({
  root:resolve(root,'demos/web/viewer'),
  base:'./',
  plugins:[sampleAssets()],
  server:{host:'127.0.0.1',port:5173,strictPort:true,fs:{allow:[root]}},
  preview:{host:'127.0.0.1',port:4173,strictPort:true},
  build:{outDir:resolve(root,'builds/web/viewer'),emptyOutDir:true,target:'es2022'},
  worker:{format:'es'}
});
