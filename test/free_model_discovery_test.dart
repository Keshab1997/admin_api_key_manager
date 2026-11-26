import 'package:admin_api_key_manager/models/free_model.dart';
import 'package:admin_api_key_manager/services/free_model_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FreeModel.fromOpenRouter', () {
    test('parses a free model by pricing 0,0', () {
      final m = FreeModel.fromOpenRouter({
        'id': 'openai/gpt-4o-mini',
        'name': 'GPT-4o Mini',
        'context_length': 128000,
        'pricing': {'prompt': '0', 'completion': '0'},
        'description': 'Fast cheap model',
      });
      expect(m.id, 'openai/gpt-4o-mini');
      expect(m.provider, 'openai');
      expect(m.isFree, isTrue);
      expect(m.contextLength, 128000);
    });

    test('parses :free suffix as free even if pricing not zero', () {
      final m = FreeModel.fromOpenRouter({
        'id': 'meta-llama/llama-3.1-8b-instruct:free',
        'name': 'Llama 3.1 8B Free',
        'pricing': {'prompt': '0.0000001', 'completion': '0.0000001'},
      });
      expect(m.isFree, isTrue);
    });

    test('paid model is not free', () {
      final m = FreeModel.fromOpenRouter({
        'id': 'openai/gpt-4o',
        'name': 'GPT-4o',
        'pricing': {'prompt': '0.005', 'completion': '0.015'},
      });
      expect(m.isFree, isFalse);
    });

    test('providerDisplay and apiKeyUrl are sensible', () {
      final m = FreeModel.fromOpenRouter({
        'id': 'google/gemini-2.0-flash:free',
        'name': 'Gemini Flash',
        'pricing': {'prompt': '0', 'completion': '0'},
      });
      expect(m.providerDisplay, 'Google');
      expect(m.apiKeyUrl, contains('aistudio.google.com'));
    });
  });

  group('filterModels', () {
    List<FreeModel> models() => [
          const FreeModel(
              id: 'openai/gpt-4o-mini',
              name: 'GPT Mini',
              provider: 'openai',
              isFree: true),
          const FreeModel(
              id: 'anthropic/claude-3',
              name: 'Claude 3',
              provider: 'anthropic',
              isFree: false),
          const FreeModel(
              id: 'meta-llama/llama-3',
              name: 'Llama 3',
              provider: 'meta-llama',
              isFree: true),
        ];

    test('freeOnly filters correctly', () {
      expect(filterModels(models(), freeOnly: true).length, 2);
      expect(filterModels(models(), freeOnly: false).length, 3);
    });

    test('provider filter', () {
      expect(filterModels(models(), provider: 'openai').first.id,
          'openai/gpt-4o-mini');
    });

    test('query search is case-insensitive', () {
      expect(filterModels(models(), query: 'CLAUDE').length, 1);
      expect(filterModels(models(), query: 'llama').length, 1);
      expect(filterModels(models(), query: 'gpt').length, 1);
    });

    test('combined query + freeOnly', () {
      expect(filterModels(models(), query: 'openai', freeOnly: true).length, 1);
      expect(
          filterModels(models(), query: 'anthropic', freeOnly: true).length, 0);
    });
  });
}
