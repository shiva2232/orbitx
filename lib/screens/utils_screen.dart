import 'package:flutter/material.dart';
import 'package:orbitx/widgets/main_sheet.dart';

class UtilPage extends StatefulWidget {
  const UtilPage({super.key});

  @override
  State<UtilPage> createState() => _UtilPageState();
}

class _UtilPageState extends State<UtilPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: ListView.builder(
            itemCount: 10,
            itemBuilder: (context, index) {
              return ListTile();
            },
          ),
        ),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AutomationBuilderSheet(),
                );
              },
              label: Icon(Icons.add_sharp),
            ),
          ],
        ),
      ],
    );
  }
}
