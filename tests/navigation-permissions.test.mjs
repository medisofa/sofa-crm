/** Access matrix baseline from main cd21e58, before the navigation regrouping. */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const source=await readFile(new URL('../js/utils/permissions.js',import.meta.url),'utf8');
const p=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const hash=xs=>createHash('sha256').update(JSON.stringify(xs.sort())).digest('hex');
const expected={
  "super_admin": {
    "allowed": "228bc22b772f220d434da32c29c128a90d28d1bc4e9bb081b93c026bba964ab7",
    "menu": "6f6639ff4b05ff8f396c47328d21a66537ddd2c752c8d7b596e2c8df5d1a2824",
    "extra": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
  },
  "admin": {
    "allowed": "8cc4651609e008ad00565cf819086aaab60398b6eb9b51fe96d76747cf86f09c",
    "menu": "801fa2d9b25789cdf614833cdec664b207ba0525a85666000a87dcc36d976f6c",
    "extra": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
  },
  "operations": {
    "allowed": "d5b752c5b96af8bd95177baeafa64e0332157a306e86f3294c891de7404e34ed",
    "menu": "23e3b2ed4c42d03a1bf75430f2331264232a540f994e9ce5184c09fe7a393baa",
    "extra": "da6d2a3b6d51d4e3a73e625684c7786587ff9c1cb0a228d77a7ce511454aaa53"
  },
  "billing": {
    "allowed": "ab9f2bf619d6a6b6a6af0001664bbe8bb9fb3ea33468de15e44a7273349524fe",
    "menu": "3af7dcef61a9258d99782cfe5452e0e44eda99330486146412c77c5781acf7ab",
    "extra": "b33d1de96d166fd67ee993579bb4ea659747391ad2aa12ac0ecfc9a0def965a7"
  },
  "glosas": {
    "allowed": "41a9f874d53d17ca1d9049d2875258125c039f81afb6c98e94c661817d875d14",
    "menu": "c2e8b957d23d88fa47cabf2f6f78f1f66a7f0142be49fa30076f5321015493e5",
    "extra": "e7a793cbbfc0e0bc9eb582e7d57cb281e5e1b350a7138057b0964b5467426dad"
  },
  "assistant": {
    "allowed": "f630d38cc4b1fda9edbfaf89aa8a3367bfde537d00bacf01b5c66642ccfae626",
    "menu": "7171d878fa612af1fe8027de8c93606e826808f006ef5620c77c15c793b8ed63",
    "extra": "e7bd1747e0bdcc27a5471430f1893cd362925da35039b3c96816e52f1570621b"
  },
  "auditor": {
    "allowed": "79736b01ef9205efaadea4d0f0dec2dc53d3935b3f2f34100ace93a16767b3fc",
    "menu": "54fdd64164220f68bda2631052f1ad981b35a1eb4ffdc7318f9d7d0c130de5e9",
    "extra": "5027e4d46b6a22a1c59a03c06cc9e841045823a75a8c72698c57508f13338157"
  },
  "client": {
    "allowed": "6c5f62f7c01540f3d1711845303fc9d14174a749c4323dcc085fc6e7f931f678",
    "menu": "8d177a71c2f653be912ca165d3a82b67c4c5917fd907692d78c8a7d0e9310a7c",
    "extra": "cf36a501f8a0e154636486475613d9c5fb1f517263a3e35b1000fa1e6d7b526f"
  },
  "capturer": {
    "allowed": "80c3445aacd0a3ba76ae191185fb01c6ff7a0e4a08bb12418397b26480b4ec46",
    "menu": "0f9f074e26ecc201293b0c1b64e450fe119c5c034b2aed4f506c8042d413607c",
    "extra": "c9b86b3cf2e32c876b57b0a0ac1d233a35267ab110cdb7f737a5f335ab4898bf"
  },
  "asistente": {
    "allowed": "510076c014898a1f9d26cf762e00244d8088e66147fcacb52a70b9882aacebc0",
    "menu": "e70cb2d59e7d769d7c55ddd1faf06f79bfb5a080f3436575140a2889ba071dd9",
    "extra": "2313c0ad52c14f8cc0048f4a6d28fbadccd5f82ba5c5bf93a72011902f073e16"
  },
  "prospect": {
    "allowed": "fa35375b260426f82d011c212cdb8de2d170a99d3a420bf172bef9fd7eed3544",
    "menu": "b1503a0792f8676e10cb70a59aaf0098d7b50a26b74c8c97780d2c2ddd9cf29f",
    "extra": "2536d84eb9f1f2d998231a73b91b0a9d3e14b571cc6b72aa0384987d15a296b0"
  }
};
for(const [role,snapshot]of Object.entries(expected)){
 assert.equal(hash(p.allRoutes().filter(i=>i.roles.includes(role)).map(i=>i.route)),snapshot.allowed,role+' allowed routes');
 assert.equal(hash(p.visibleNav(role).flatMap(g=>g.items.map(i=>i.route))),snapshot.menu,role+' menu routes');
 assert.equal(hash(p.extraNav(role).map(i=>i.route)),snapshot.extra,role+' extra routes');
}
p.aplicarMenu({admin:{contratos:{en_menu:false}},client:{usuarios:{en_menu:true}}});
assert.equal(p.visibleNav('admin').flatMap(g=>g.items).some(i=>i.route==='contratos'),false);
assert.equal(p.extraNav('admin').some(i=>i.route==='contratos'),true);
assert.equal(p.canSee('usuarios','client'),false);
p.olvidarMenu();
console.log('PASS: 11 role baselines unchanged, menu overrides respected, no added privileges.');
