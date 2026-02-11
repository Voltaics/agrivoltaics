/// Service for centralizing validation utilities across the application.
/// Provides consistent validation patterns and error messages.
class ValidatorsService {
  // Singleton instance
  static final ValidatorsService _instance = ValidatorsService._internal();

  factory ValidatorsService() {
    return _instance;
  }

  ValidatorsService._internal();

  // Regular expressions for common validations
  static const String _emailRegex =
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$';

  static const String _nameRegex = r"^[a-zA-Z\s'-]{2,50}$";
  static const String _alphanumericRegex = r'^[a-zA-Z0-9_-]{3,50}$';
  static const String _urlRegex =
      r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$';

  /// Validate email format
  /// Returns error message if invalid, null if valid
  String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Email is required';
    }

    email = email.trim();

    if (email.length > 254) {
      return 'Email is too long';
    }

    if (!RegExp(_emailRegex).hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validate person's name
  /// Returns error message if invalid, null if valid
  String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Name is required';
    }

    name = name.trim();

    if (name.length < 2) {
      return 'Name must be at least 2 characters';
    }

    if (name.length > 50) {
      return 'Name must be less than 50 characters';
    }

    if (!RegExp(_nameRegex).hasMatch(name)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }

    return null;
  }

  /// Validate text field (not empty, within length)
  /// Returns error message if invalid, null if valid
  String? validateText(String? text, {
    String fieldName = 'This field',
    int minLength = 1,
    int maxLength = 255,
    bool required = true,
  }) {
    if (text == null || text.trim().isEmpty) {
      if (required) {
        return '$fieldName is required';
      }
      return null;
    }

    text = text.trim();

    if (text.length < minLength) {
      return '$fieldName must be at least $minLength character${minLength > 1 ? 's' : ''}';
    }

    if (text.length > maxLength) {
      return '$fieldName must be less than $maxLength characters';
    }

    return null;
  }

  /// Validate numeric value within range
  /// Returns error message if invalid, null if valid
  String? validateNumber(String? value, {
    String fieldName = 'This field',
    double? min,
    double? max,
    bool required = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      if (required) {
        return '$fieldName is required';
      }
      return null;
    }

    final number = double.tryParse(value);

    if (number == null) {
      return '$fieldName must be a valid number';
    }

    if (min != null && number < min) {
      return '$fieldName must be at least $min';
    }

    if (max != null && number > max) {
      return '$fieldName must be at most $max';
    }

    return null;
  }

  /// Validate latitude
  /// Valid range: -90 to 90
  String? validateLatitude(String? value) {
    return validateNumber(
      value,
      fieldName: 'Latitude',
      min: -90,
      max: 90,
      required: false,
    );
  }

  /// Validate longitude
  /// Valid range: -180 to 180
  String? validateLongitude(String? value) {
    return validateNumber(
      value,
      fieldName: 'Longitude',
      min: -180,
      max: 180,
      required: false,
    );
  }

  /// Validate URL format
  /// Returns error message if invalid, null if valid
  String? validateUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return 'URL is required';
    }

    url = url.trim();

    if (!RegExp(_urlRegex).hasMatch(url)) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  /// Validate alphanumeric identifier (sensor name, zone name, etc.)
  /// Allows letters, numbers, hyphens, and underscores
  String? validateIdentifier(String? value, {
    String fieldName = 'This field',
    int minLength = 3,
    int maxLength = 50,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    value = value.trim();

    if (value.length < minLength) {
      return '$fieldName must be at least $minLength characters';
    }

    if (value.length > maxLength) {
      return '$fieldName must be less than $maxLength characters';
    }

    if (!RegExp(_alphanumericRegex).hasMatch(value)) {
      return '$fieldName can only contain letters, numbers, hyphens, and underscores';
    }

    return null;
  }

  /// Check if text is empty or whitespace only
  bool isEmpty(String? text) {
    return text == null || text.trim().isEmpty;
  }

  /// Check if text is not empty
  bool isNotEmpty(String? text) {
    return !isEmpty(text);
  }

  /// Check if two passwords match
  String? validatePasswordMatch(String? password1, String? password2) {
    if (isEmpty(password1) || isEmpty(password2)) {
      return 'Both passwords are required';
    }

    if (password1 != password2) {
      return 'Passwords do not match';
    }

    return null;
  }

  /// Validate password strength
  /// Returns error message if invalid, null if valid
  String? validatePasswordStrength(String? password, {
    bool requireUppercase = true,
    bool requireLowercase = true,
    bool requireNumbers = true,
    bool requireSpecialChars = true,
    int minLength = 8,
  }) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }

    if (password.length < minLength) {
      return 'Password must be at least $minLength characters';
    }

    if (requireUppercase && !password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }

    if (requireLowercase && !password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }

    if (requireNumbers && !password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }

    if (requireSpecialChars && !password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }

    return null;
  }

  /// Validate that a value is one of the allowed options
  String? validateInList(String? value, List<String> allowedValues, {
    String fieldName = 'This field',
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    if (!allowedValues.contains(value.trim())) {
      return '$fieldName must be one of: ${allowedValues.join(', ')}';
    }

    return null;
  }
}
