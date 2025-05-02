part of 'main.dart';

abstract class IdeEvent {}

class InitializeIdeEvent extends IdeEvent {}

class CreateProjectEvent extends IdeEvent {}

class OpenProjectEvent extends IdeEvent {}

class OpenFileEvent extends IdeEvent {
  final String? path;
  OpenFileEvent({this.path});
}

class SaveFileEvent extends IdeEvent {}

class RunCodeEvent extends IdeEvent {}

class StartDebuggingEvent extends IdeEvent {}

class StepDebugEvent extends IdeEvent {}

class StopDebuggingEvent extends IdeEvent {}

class GitCommitEvent extends IdeEvent {}

class GitPushEvent extends IdeEvent {}

class GitPullEvent extends IdeEvent {}

class SelectTabEvent extends IdeEvent {
  final int index;
  SelectTabEvent(this.index);
}

class CloseTabEvent extends IdeEvent {
  final int index;
  CloseTabEvent(this.index);
}

class ToggleBreakpointEvent extends IdeEvent {
  final int line;
  ToggleBreakpointEvent(this.line);
}

class ToggleThemeEvent extends IdeEvent {}

class DragStartedEvent extends IdeEvent {}

class DragEndedEvent extends IdeEvent {}

class FileDroppedEvent extends IdeEvent {
  final String path;
  FileDroppedEvent(this.path);
}

class UpdateTabContentEvent extends IdeEvent {
  final int tabIndex;
  final String content;
  UpdateTabContentEvent(this.tabIndex, this.content);
}

class UpdateDebugInputEvent extends IdeEvent {
  final String input;
  UpdateDebugInputEvent(this.input);
}
