/**********************************************
 * Improved Test Workflow Orchestration Script
 *
 * This script triggers multiple GitHub Actions
 * workflows in batched parallel mode, waits
 * for each to complete, and moves on to the
 * next batch until all workflows finish.
 **********************************************/

// const WORKFLOWS_SET = new Set([
//   'login-nc-v27.yml',
//   'login-nc-v28.yml',
//   'login-oc-v10.yml',
//   'login-ocis-v5.yml',
//   'login-os-v1.yml',
//   'login-sf-v11.yml',
//   'share-link-nc-v27-nc-v27.yml',
//   'share-link-nc-v27-nc-v28.yml',
//   'share-link-nc-v27-oc-v10.yml',
//   'share-link-nc-v27-os-v1.yml',
//   'share-link-nc-v28-nc-v27.yml',
//   'share-link-nc-v28-nc-v28.yml',
//   'share-link-nc-v28-oc-v10.yml',
//   'share-link-oc-v10-nc-v27.yml',
//   'share-link-oc-v10-nc-v28.yml',
//   'share-link-oc-v10-oc-v10.yml',
//   'share-with-nc-v27-nc-v27.yml',
//   'share-with-nc-v27-nc-v28.yml',
//   'share-with-nc-v27-oc-v10.yml',
//   'share-with-nc-v27-os-v1.yml',
//   'share-with-nc-v28-nc-v27.yml',
//   'share-with-nc-v28-nc-v28.yml',
//   'share-with-nc-v28-oc-v10.yml',
//   'share-with-nc-v28-os-v1.yml',
//   'share-with-oc-v10-nc-v27.yml',
//   'share-with-oc-v10-nc-v28.yml',
//   'share-with-oc-v10-oc-v10.yml',
//   'share-with-oc-v10-os-v1.yml',
//   'share-with-os-v1-nc-v27.yml',
//   'share-with-os-v1-nc-v28.yml',
//   'share-with-os-v1-oc-v10.yml',
//   'share-with-os-v1-os-v1.yml',
//   'share-with-sf-v11-sf-v11.yml',
//   'invite-link-nc-sm-v27-nc-sm-v27.yml',
//   'invite-link-nc-sm-v27-oc-sm-v10.yml',
//   'invite-link-nc-sm-v27-ocis-v5.yml',
//   'invite-link-oc-sm-v10-nc-sm-v27.yml',
//   'invite-link-oc-sm-v10-oc-sm-v10.yml',
//   'invite-link-oc-sm-v10-ocis-v5.yml',
//   'invite-link-ocis-v5-nc-sm-v27.yml',
//   'invite-link-ocis-v5-oc-sm-v10.yml',
//   'invite-link-ocis-v5-ocis-v5.yml'
// ]);

const WORKFLOWS_SET = new Set([
  'login-nc-v29.yml',


  'share-link-nc-v27-nc-v29.yml',
  'share-link-nc-v28-nc-v29.yml',
  'share-link-nc-v28-os-v1.yml',
  'share-link-nc-v29-nc-v27.yml',
  'share-link-nc-v29-nc-v28.yml',
  'share-link-nc-v29-nc-v29.yml',
  'share-link-nc-v29-oc-v10.yml',
  'share-link-nc-v29-os-v1.yml',
  'share-link-oc-v10-nc-v29.yml',

  'share-with-nc-v27-nc-v29.yml',
  'share-with-nc-v28-nc-v29.yml',
  'share-with-nc-v29-nc-v27.yml',
  'share-with-nc-v29-nc-v28.yml',
  'share-with-nc-v29-nc-v29.yml',
  'share-with-nc-v29-oc-v10.yml',
  'share-with-nc-v29-os-v1.yml',
  
  'share-with-oc-v10-nc-v29.yml',
  'share-with-os-v1-nc-v29.yml',
]);

// @MahdiBaghbani: Some kind of a safegaurd against accidentally 
// duplicate values in the above list
const WORKFLOWS = Array.from(WORKFLOWS_SET);

// Workflows in this list may fail without marking the whole matrix red
const EXPECTED_FAILURES = new Set([
  'share-link-oc-v10-nc-v27.yml',
  'share-link-oc-v10-nc-v28.yml',
  'share-link-oc-v10-nc-v29.yml',
]);

// Constants controlling polling / batching behavior
const POLL_INTERVAL_STATUS = 30000; // ms between each run status check
const POLL_INTERVAL_RUN_ID = 5000;  // ms between each new run ID check
const RUN_ID_TIMEOUT = 60000;       // ms to wait for a new run to appear
const INITIAL_RUN_ID_DELAY = 5000;  // ms initial wait before checking for run ID
const DEFAULT_BATCH_SIZE = 5;       // Workflows to run concurrently per batch

/**
 * Pause execution for the given number of milliseconds.
 * @param {number} ms - Milliseconds to sleep.
 * @returns {Promise<void>}
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wait until a given workflow run completes by polling its status.
 * @param {Object} github - GitHub API client.
 * @param {string} owner - Repository owner.
 * @param {string} repo - Repository name.
 * @param {number} runId - Workflow run ID.
 * @returns {Promise<string>} Conclusion of the workflow (e.g. 'success' or 'failure').
 */
async function waitForWorkflowCompletion(github, owner, repo, runId) {
  while (true) {
    try {
      const { data: run } = await github.rest.actions.getWorkflowRun({
        owner,
        repo,
        run_id: runId
      });

      if (run.status === 'completed') {
        return run.conclusion;
      }
    } catch (error) {
      console.error(`Error fetching run ${runId}: ${error.message}`);
    }
    await sleep(POLL_INTERVAL_STATUS);
  }
}

/**
 * Find the run ID of a newly triggered workflow by polling for an 'in_progress' run.
 * @param {Object} github - GitHub API client.
 * @param {Object} params - { owner, repo, workflow_id, branch } for the GitHub API.
 * @returns {Promise<number>} The detected run ID of the new workflow.
 * @throws If no new run is found within the timeout.
 */
async function findNewRunId(github, params) {
  await sleep(INITIAL_RUN_ID_DELAY);
  const startTime = Date.now();

  while (Date.now() - startTime < RUN_ID_TIMEOUT) {
    try {
      const { data: runs } = await github.rest.actions.listWorkflowRuns({
        ...params,
        status: 'in_progress',
        per_page: 1
      });

      if (runs.total_count > 0 && runs.workflow_runs.length > 0) {
        return runs.workflow_runs[0].id;
      }
    } catch (error) {
      console.error(`Error listing runs for workflow ${params.workflow_id}: ${error.message}`);
    }
    await sleep(POLL_INTERVAL_RUN_ID);
  }
  throw new Error(
    `Timeout: No in-progress run found for workflow ${params.workflow_id} within ${RUN_ID_TIMEOUT} ms`
  );
}

/**
 * Dispatch a workflow and retrieve the run ID once it's in progress.
 * @param {Object} github - GitHub API client.
 * @param {Object} context - GitHub Actions context (includes repo/owner/ref).
 * @param {string} workflow - Workflow file name to trigger.
 * @returns {Promise<{ name: string, runId: number }>} Name and runId of triggered workflow.
 */
async function triggerWorkflow(github, context, workflow) {
  console.log(`Triggering workflow: ${workflow}`);
  const { owner, repo } = context.repo;

  // Dispatch the workflow
  await github.rest.actions.createWorkflowDispatch({
    owner,
    repo,
    workflow_id: workflow,
    ref: context.ref
  });

  // Infer branch name from ref (e.g. 'refs/heads/main' -> 'main')
  const branch = context.ref.replace(/^refs\/heads\//, '');
  const runId = await findNewRunId(github, {
    owner,
    repo,
    workflow_id: workflow,
    branch
  });

  return { name: workflow, runId };
}

/**
 * Main orchestration entry point.
* Batches workflows, triggers them in parallel, then waits for completion.
 * Moves on to the next batch until all workflows finish.
 *
 * @param {Object} github - GitHub API client.
 * @param {Object} context - GitHub Actions context.
 * @param {Object} core - actions/core object injected by github-script.
 */
module.exports = async function orchestrateTests(github, context, core) {
  const total = WORKFLOWS.length;
  const batchSize = DEFAULT_BATCH_SIZE;
  const totalBatches = Math.ceil(total / batchSize);
  // {name, runId, conclusion}
  const results = [];
  let processed = 0;
  let allSucceeded = true;

  console.log(`Orchestrating ${total} workflows in batches of ${batchSize}, ${totalBatches} batches to go …`);

  for (let i = 0; i < total; i += batchSize) {
    const batchNumber = Math.floor(i / batchSize) + 1;
    console.log(`\nProcessing batch ${batchNumber} of ${totalBatches} …`);
    const batch = WORKFLOWS.slice(i, i + batchSize);

    await Promise.all(batch.map(async wf => {
      try {
        const { name, runId } = await triggerWorkflow(github, context, wf);
        const concl = await waitForWorkflowCompletion(
          github, context.repo.owner, context.repo.repo, runId);
        results.push({ name, runId, conclusion: concl });
        if (concl !== 'success' && !EXPECTED_FAILURES.has(name)) {
          allSucceeded = false;
        }
      } catch (e) {
        results.push({ name: wf, runId: 0, conclusion: 'failure' });
        allSucceeded = false;
        console.error(e.message);
      }
      processed++;
      console.log(`${processed}/${total} done`);
    }));
  }

  // summary 
  const passed = results.filter(r => r.conclusion === 'success' || EXPECTED_FAILURES.has(r.name)).length;
  const failed = total - passed;
  const pct = Math.round((passed / total) * 100);
  const barUnits = Math.round((passed / total) * 20);
  const bar = '▉'.repeat(barUnits) + '▏'.repeat(20 - barUnits);

  await core.summary
    .addHeading('🚀 OCM Test Suite Report')
    .addRaw(`**${passed}/${total} passed - ${pct}%**  \n`)
    .addRaw(`\`${bar}\`  \n`)
    .addTable([
      [{ header: true, data: 'Workflow' }, { header: true, data: 'Result' }],
      ...results.map(r => {
        const link = r.runId
          ? `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${r.runId}`
          : '';
        const label =
          r.conclusion === 'success' ? '✅ success' :
            EXPECTED_FAILURES.has(r.name) ? '⚠️ allowed-failure' :
              '❌ failure';
        return [link ? `<a href="${link}">${r.name}</a>` : r.name, label];
      })
    ])
    .addBreak()
    .addRaw(`<details><summary>🔍 Failing workflows (${failed})</summary>\n\n` +
      results.filter(r => r.conclusion !== 'success')
        .map(r => `* **${r.name}**`).join('\n') +
      '\n\n</details>')
    .addBreak()
    .addRaw(allSucceeded ? '🎉 **Test Suite succeeded**' : '⚠️ **Failures present**')
    .write();

  return results;
};
