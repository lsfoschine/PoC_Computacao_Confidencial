const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');
const grpc = require('@grpc/grpc-js');
const { connect, signers } = require('@hyperledger/fabric-gateway');


function getGitCommit() {
    try { return execSync('git rev-parse --short HEAD').toString().trim(); } catch (e) { return 'nogit'; }
}

function hashFile(filepath) {
    if (!fs.existsSync(filepath)) return "missing";
    return crypto.createHash('sha256').update(fs.readFileSync(filepath)).digest('hex');
}

function percentile(arr, p) {
    if (arr.length === 0) return 0.0;
    const sorted = arr.slice().sort((a, b) => a - b);
    const pos = (sorted.length - 1) * p;
    const base = Math.floor(pos);
    const rest = pos - base;
    return (sorted[base + 1] !== undefined) ? sorted[base] + rest * (sorted[base + 1] - sorted[base]) : sorted[base];
}


const cryptoPath = path.resolve(process.env.HOME, 'fabric-samples/test-network/organizations/peerOrganizations/org1.example.com');
const certPath = path.resolve(cryptoPath, 'users/User1@org1.example.com/msp/signcerts/cert.pem');
const keyDirectoryPath = path.resolve(cryptoPath, 'users/User1@org1.example.com/msp/keystore');
const tlsCertPath = path.resolve(cryptoPath, 'peers/peer0.org1.example.com/tls/ca.crt');

const peerEndpoint = 'localhost:7051';
const peerHostAlias = 'peer0.org1.example.com';
const channelName = 'mychannel';
const chaincodeName = 'basic';

async function initContract() {
    const credentials = fs.readFileSync(certPath);
    const identity = { mspId: 'Org1MSP', credentials };
    const keyPath = path.resolve(keyDirectoryPath, fs.readdirSync(keyDirectoryPath)[0]);
    const signer = signers.newPrivateKeySigner(crypto.createPrivateKey(fs.readFileSync(keyPath)));
    const client = new grpc.Client(peerEndpoint, grpc.credentials.createSsl(fs.readFileSync(tlsCertPath)), {
        'grpc.ssl_target_name_override': peerHostAlias,
    });
    const gateway = connect({ client, identity, signer });
    return gateway.getNetwork(channelName).getContract(chaincodeName);
}


async function main() {
    // 1. Leitura de Argumentos
    const args = process.argv.slice(2);
    let params = { tps: 100, corpus: '', outdir: '', duration: 60 }; // Duração fixa de 60s por round
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--tps') params.tps = parseInt(args[++i]);
        if (args[i] === '--corpus') params.corpus = args[++i];
        if (args[i] === '--outdir') params.outdir = args[++i];
    }

    console.log(`[*] Iniciando Fabric Benchmark Nativo | Alvo: ${params.tps} TPS por ${params.duration}s`);

    // 2. Criação do Ambiente de Log
    const timestampIso = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    const runId = `${timestampIso.replace(/[-:]/g, '').replace('Z', '')}-${os.hostname()}-${getGitCommit()}-TPS${params.tps}`;
    const outDir = params.outdir || `results/${runId}`;
    if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

    const docs = [];
    const lines = fs.readFileSync(params.corpus, 'utf-8').split('\n');
    for (let line of lines) {
        if (line.trim()) docs.push(JSON.parse(line).text);
    }
    const nDocsTotal = docs.length;

    const contract = await initContract();
    
    const totalTx = params.tps * params.duration;
    const intervalMs = 1000 / params.tps;
    const latencies = [];
    
    let successCount = 0;
    let failCount = 0; 
    const promises = [];

    const globalStartTime = Date.now();

    for (let i = 0; i < totalTx; i++) {
        // Controle da taxa de TPS
        const expectedTime = globalStartTime + (i * intervalMs);
        const now = Date.now();
        if (now < expectedTime) {
            await new Promise(r => setTimeout(r, expectedTime - now));
        }

        const docText = docs[i % nDocsTotal];
        const docHash = crypto.createHash('sha256').update(docText).digest('hex');
        
        const assetId = `Asset_${docHash.substring(0, 16)}_${i}`;
        const owner = `Owner_${docHash.substring(0, 8)}`;

        const txStart = Date.now();
        
        const p = contract.submitTransaction('CreateAsset', assetId, 'corpus_data', '1', owner, '100')
            .then(() => {
                successCount++;
                latencies.push(Date.now() - txStart);
            })
            .catch((err) => { 
                failCount++; 
            });
        
        promises.push(p);
    }

    await Promise.all(promises);
    const totalTimeSec = (Date.now() - globalStartTime) / 1000;

    const tpsReal = totalTimeSec > 0 ? successCount / totalTimeSec : 0;
    const p50Ms = percentile(latencies, 0.50);
    const p95Ms = percentile(latencies, 0.95);

    const runRecord = {
        run_id: runId,
        timestamp: timestampIso,
        model_id: "Fabric/CreateAsset-Native",
        max_length: params.tps, 
        batch: 1,
        threads: 0, 
        n_docs_total: totalTx,
        n_docs_measured: successCount,
        p50_ms: Number(p50Ms.toFixed(3)),
        p95_ms: Number(p95Ms.toFixed(3)),
        docs_per_sec: Number(tpsReal.toFixed(6)),
        total_seconds_measured: Number(totalTimeSec.toFixed(6)),
        corpus_sha256: hashFile(params.corpus),
        embeddings_sha256: hashFile(__filename)
    };

    fs.writeFileSync(path.join(outDir, 'run.jsonl'), JSON.stringify(runRecord) + '\n');
    
    console.log(`[✓] Carga de ${params.tps} TPS Concluída!`);
    console.log(`    ↳ Sucesso: ${successCount} | Falhas: ${failCount} | Total Tentado: ${totalTx}`);
    console.log(`    ↳ TPS Real: ${tpsReal.toFixed(2)} | P50: ${p50Ms.toFixed(2)}ms\n`);
    
    process.exit(0);
}

main().catch(console.error);