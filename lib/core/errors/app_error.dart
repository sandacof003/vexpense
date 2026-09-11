import '../data/repositories/account_repository.dart';

sealed class AppError implements Exception {
  const AppError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ValidationError extends AppError {
  const ValidationError(super.message);
}

class ConstraintError extends AppError {
  const ConstraintError(super.message);
}

class StorageError extends AppError {
  const StorageError(super.message);
}

class UnknownAppError extends AppError {
  const UnknownAppError(super.message);
}

AppError mapAppError(Object error) {
  if (error is AppError) return error;
  if (error is ArgumentError) {
    return ValidationError(error.message?.toString() ?? error.toString());
  }
  if (error is DuplicateNameException || error is AccountInUseException) {
    return ConstraintError(error.toString());
  }
  if (error is StateError) return StorageError(error.toString());
  return UnknownAppError(error.toString());
}
