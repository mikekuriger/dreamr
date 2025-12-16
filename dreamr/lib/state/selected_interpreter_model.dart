// state/selected_interpreter_model.dart
import 'package:flutter/foundation.dart';
import 'package:dreamr/models/interpreter.dart';

class SelectedInterpreterModel extends ChangeNotifier {
  Interpreter? _selectedInterpreter;

  Interpreter? get selectedInterpreter => _selectedInterpreter;

  void setSelectedInterpreter(Interpreter? interpreter) {
    _selectedInterpreter = interpreter;
    notifyListeners();
  }
}