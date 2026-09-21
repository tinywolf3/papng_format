import { defineConfig } from '@playwright/test';
import { fileURLToPath } from 'node:url';

const root=fileURLToPath(new URL('../',import.meta.url));
export default defineConfig({
  testDir:'.',testMatch:'**/*.spec.ts',fullyParallel:false,workers:1,
  timeout:30000,expect:{timeout:8000},
  outputDir:`${root}/builds/web/viewer-tests/results`,
  reporter:[['list'],['html',{outputFolder:`${root}/builds/web/viewer-tests/report`,open:'never'}]],
  use:{baseURL:'http://127.0.0.1:4173',browserName:'chromium',viewport:{width:1440,height:1100},trace:'retain-on-failure'},
  webServer:{command:'npm run preview',cwd:root,url:'http://127.0.0.1:4173',reuseExistingServer:false,timeout:30000},
});
