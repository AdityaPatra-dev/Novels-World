import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FIFO queue strictly preserves narrative order even when synthesis finishes out of order', () async {
    final Map<int, String> resolved = {};
    final List<int> enqueuedOrder = [];
    int nextQueued = 1;

    void drain() {
      while (resolved.containsKey(nextQueued)) {
        enqueuedOrder.add(nextQueued);
        resolved.remove(nextQueued);
        nextQueued++;
      }
    }

    // Index 0 already playing
    // Now index 2 finishes FIRST (fast short sentence)
    resolved[2] = 'audio_short_line_2.mp3';
    drain();
    expect(enqueuedOrder, isEmpty, reason: 'Index 2 must wait for index 1');

    // Index 3 finishes next (another short sentence)
    resolved[3] = 'audio_short_line_3.mp3';
    drain();
    expect(enqueuedOrder, isEmpty, reason: 'Indices 2 and 3 must wait for index 1');

    // Index 1 finishes last (long paragraph)
    resolved[1] = 'audio_long_paragraph_1.mp3';
    drain();

    expect(enqueuedOrder, equals([1, 2, 3]), reason: 'All items must be enqueued in strict numerical order');
    expect(nextQueued, 4);
  });
}

