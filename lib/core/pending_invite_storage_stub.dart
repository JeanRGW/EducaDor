final _values = <String, String>{};
String? readStoredInvite(String key) => _values[key];
void writeStoredInvite(String key, String? value) {
  if (value == null) {
    _values.remove(key);
  } else {
    _values[key] = value;
  }
}
