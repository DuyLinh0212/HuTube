import { RuntimeConfig } from './runtime-config';

describe('Recommendation service configuration', () => {
  async function load(apiBaseUrl: string, recommendationBaseUrl?: string) {
    spyOn(globalThis, 'fetch').and.callFake(async input => new Response(JSON.stringify(
      input === 'config.json'
        ? { API_BASE_URL: apiBaseUrl, RECOMMENDATION_BASE_URL: recommendationBaseUrl }
        : {}
    ), { status: 200 }));
    const config = new RuntimeConfig();
    await config.load();
    return config;
  }

  it('uses the deployed recommendation service when no explicit URL is set', async () => {
    const config = await load('https://api.example.test/api/v1');
    expect(config.recommendationBaseUrl).toBe('https://recommendation.dalitu.app/api/v1');
  });

  it('preserves an explicitly configured recommendation service', async () => {
    const config = await load('https://api.example.test/api/v1', 'https://recommendation.example.test/api/v1/');
    expect(config.recommendationBaseUrl).toBe('https://recommendation.example.test/api/v1');
  });

  for (const service of ['hutube-recommendation-service', 'hutube-recommendation-services']) {
    it(`uses the local service when previewing the ${service} configuration locally`, async () => {
      const config = await load('http://localhost:5080/api/v1', `https://${service}.onrender.com/api/v1`);
      expect(config.recommendationBaseUrl).toBe('http://localhost:8000/api/v1');
    });
  }

  it('uses local services when previewing the EC2 configuration locally', async () => {
    const config = await load(
      'https://api.dalitu.app/api/v1',
      'https://recommendation.dalitu.app/api/v1',
    );
    expect(config.apiBaseUrl).toBe('http://localhost:5080/api/v1');
    expect(config.recommendationBaseUrl).toBe('http://localhost:8000/api/v1');
  });
});
