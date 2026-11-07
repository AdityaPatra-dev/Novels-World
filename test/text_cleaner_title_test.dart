import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';

void main() {
  group('TextCleaner.cleanNovelTitle Tests', () {
    test('strips promotional "Read [Title] Online for Free" prefixes and suffixes', () {
      expect(
        TextCleaner.cleanNovelTitle('Read Shadow Slave Online for Free'),
        equals('Shadow Slave'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Read The Great Gatsby Online for Free by F. Scott Fitzgerald'),
        equals('The Great Gatsby'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Read Novel Solo Leveling Online'),
        equals('Solo Leveling'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Free Web Novel Lord of the Mysteries'),
        equals('Lord of the Mysteries'),
      );
    });

    test('strips trailing site watermarks, aggregator names, and branding', () {
      expect(
        TextCleaner.cleanNovelTitle('Shadow Slave - NovelFull'),
        equals('Shadow Slave'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Solo Leveling | ReadNovelFull'),
        equals('Solo Leveling'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Reverend Insanity - Free Web Novel'),
        equals('Reverend Insanity'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Martial Peak - BoxNovel.com'),
        equals('Martial Peak'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Super Gene - LibRead'),
        equals('Super Gene'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Cultivation Online - ReadWN'),
        equals('Cultivation Online'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Nano Machine - AsuraScans'),
        equals('Nano Machine'),
      );
    });

    test('strips bracketed format tags and leaked status badges', () {
      expect(
        TextCleaner.cleanNovelTitle('Solo Leveling (Web Novel)'),
        equals('Solo Leveling'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Overlord (Light Novel)'),
        equals('Overlord'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Mother of Learning (WN)'),
        equals('Mother of Learning'),
      );
      expect(
        TextCleaner.cleanNovelTitle('[HOT] Shadow Slave'),
        equals('Shadow Slave'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Solo Leveling HOT'),
        equals('Solo Leveling'),
      );
      expect(
        TextCleaner.cleanNovelTitle('Martial Peak COMPLETED'),
        equals('Martial Peak'),
      );
      expect(
        TextCleaner.cleanNovelTitle('The Beginning After The End [Completed]'),
        equals('The Beginning After The End'),
      );
    });

    test('strips trailing chapter numbers in title', () {
      expect(
        TextCleaner.cleanNovelTitle("Omniscient Reader's Viewpoint - Chapter 1 - 551"),
        equals("Omniscient Reader's Viewpoint"),
      );
      expect(
        TextCleaner.cleanNovelTitle('Shadow Slave - 1 - 2500'),
        equals('Shadow Slave'),
      );
    });

    test('decodes HTML entities and cleans newlines', () {
      expect(
        TextCleaner.cleanNovelTitle("The Hero&#039;s &amp; Villain&#039;s Tale"),
        equals("The Hero's & Villain's Tale"),
      );
      expect(
        TextCleaner.cleanNovelTitle("Shadow\nSlave\r\nOnline"),
        equals('Shadow Slave'),
      );
    });

    test('preserves genuine multi-word clean titles untouched', () {
      expect(TextCleaner.cleanNovelTitle('Solo Leveling'), equals('Solo Leveling'));
      expect(TextCleaner.cleanNovelTitle('Shadow Slave'), equals('Shadow Slave'));
      expect(TextCleaner.cleanNovelTitle('Lord of the Mysteries'), equals('Lord of the Mysteries'));
      expect(TextCleaner.cleanNovelTitle('The Beginning After The End'), equals('The Beginning After The End'));
      expect(TextCleaner.cleanNovelTitle('A Game of Thrones'), equals('A Game of Thrones'));
    });
  });
}
