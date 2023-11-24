import 'package:blood_pressure_app/components/dialoges/oldinput_dialoge.dart';
import 'package:flutter/material.dart';

/// Widget for editing numbers in a list tile.
class NumberInputListTile extends StatelessWidget {
  /// Creates a widget for editing numbers in a list tile.
  const NumberInputListTile(
      {super.key,
        required this.label,
        this.leading,
        this.value,
        required this.onParsableSubmit,});

  /// Short label describing the required field contents.
  ///
  /// This will be both the title of the list tile as well as the hint text in the input dialoge.
  final String label;

  /// Widget to display before the label in the list tile.
  final Widget? leading;

  /// Current content of the input field.
  final num? value;

  /// Gets called once the user submits a new valid number to the field.
  final NumberInputResult onParsableSubmit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value.toString()),
      leading: leading,
      trailing: const Icon(Icons.edit),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => NumberInputDialoge(
            initialValue: value?.toString(),
            hintText: label,
            onParsableSubmit: (value) {
              Navigator.of(context).pop();
              onParsableSubmit(value);
            },
          ),
        );
      },
    );
  }
}