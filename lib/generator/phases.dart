library jaguar.generator.phases;

import 'dart:io';

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:yaml/yaml.dart';

import 'api_annotation.dart';
import 'pre_processor/pre_processor_function_annotation_generator.dart';
import 'post_processor/post_processor_function_annotation_generator.dart';

String getProjectName() {
  File pubspec = new File('./pubspec.yaml');
  String content = pubspec.readAsStringSync();
  var doc = loadYaml(content);
  return doc['name'];
}

List<String> getAnnotations() {
  File pubspec = new File('./jaguar.yaml');
  String content = pubspec.readAsStringSync();
  var doc = loadYaml(content);
  return doc['apis'];
}

List<String> getPreProcessor() {
  File pubspec = new File('./jaguar.yaml');
  String content = pubspec.readAsStringSync();
  var doc = loadYaml(content);
  return doc['pre_processors'] == null ? <String>[] : doc['pre_processors'];
}

List<String> getPostProcessor() {
  File pubspec = new File('./jaguar.yaml');
  String content = pubspec.readAsStringSync();
  var doc = loadYaml(content);
  return doc['post_processors'] == null ? <String>[] : doc['post_processors'];
}

Phase postProcessorPhase(String projectName, List<String> postProcessors) {
  return new Phase()
    ..addAction(
        new GeneratorBuilder(const [
          const PostProcessorFunctionAnnotationGenerator(),
        ]),
        new InputSet(projectName, postProcessors));
}

Phase preProcessorPhase(String projectName, List<String> preProcessors) {
  return new Phase()
    ..addAction(
        new GeneratorBuilder(const [
          const PreProcessorFunctionAnnotationGenerator(),
        ]),
        new InputSet(projectName, preProcessors));
}

Phase apisPhase(String projectName, List<String> apis) {
  return new Phase()
    ..addAction(
        new GeneratorBuilder(const [
          const ApiAnnotationGenerator(),
        ]),
        new InputSet(projectName, apis));
}

PhaseGroup generatePhaseGroup(
    {String projectName,
    List<String> postProcessors,
    List<String> preProcessors,
    List<String> apis}) {
  return new PhaseGroup()
    ..addPhase(postProcessorPhase(projectName, postProcessors))
    ..addPhase(preProcessorPhase(projectName, preProcessors))
    ..addPhase(apisPhase(projectName, apis));
}

PhaseGroup phaseGroup() {
  String projectName = getProjectName();
  if (projectName == null) {
    throw "Could not find the project name";
  }
  List<String> apis = getAnnotations();
  List<String> postProcessor = getPostProcessor();
  List<String> preProcessor = getPreProcessor();
  return generatePhaseGroup(
      projectName: projectName,
      postProcessors: postProcessor,
      preProcessors: preProcessor,
      apis: apis);
}