#!/usr/bin/env node
import { asArray, azdValue, jsonRequest, main, request } from './_utils.mjs';

main(async () => {
  console.log('=== verify-smart-todo ===');
  const api = azdValue('API_URL');
  const listUrl = `${api}/api/todos?userId=user-1`;
  const { data: initial } = await jsonRequest(listUrl);
  if (asArray(initial).length === 0) throw new Error('Seed todo list is empty');
  let todoId;
  try {
    const { data: created } = await jsonRequest(`${api}/api/todos`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ title: 'Portable verifier smoke test', userId: 'user-1' }),
    }, [201]);
    todoId = created?.id;
    if (!todoId) throw new Error('Create response did not include an id');
    const { data: generated } = await jsonRequest(`${api}/api/todos/${todoId}/generate-steps`, { method: 'POST', timeoutMs: 120000 });
    const directSteps = asArray(generated, ['steps']);
    const steps = directSteps.length ? directSteps : asArray(generated?.todo, ['steps']);
    if (steps.length < 3 || steps.length > 7) throw new Error(`Expected 3-7 generated steps, received ${steps.length}`);
    const step = steps[0];
    if (!step?.id) throw new Error('Generated step did not include an id');
    await jsonRequest(`${api}/api/todos/${todoId}/steps/${step.id}`, {
      method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ isCompleted: true }),
    });
    const loaded = await jsonRequest(`${api}/api/todos/${todoId}`);
    if (!loaded.data) throw new Error('Created todo could not be fetched');
  } finally {
    if (todoId) {
      const deletion = await request(`${api}/api/todos/${todoId}`, { method: 'DELETE', timeoutMs: 60000 });
      if (deletion.status !== 204) throw new Error(`Cleanup delete returned HTTP ${deletion.status}`);
    }
  }
  const { data: finalList } = await jsonRequest(listUrl);
  if (asArray(finalList).some((todo) => todo.id === todoId)) throw new Error('Deleted verifier todo is still present');
  console.log('PASS: seed, create, AI steps, step completion, fetch, delete, and final absence');
});
