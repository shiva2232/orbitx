import 'package:flutter/material.dart';
import 'package:orbitx/helper/rv_automation.dart';
import 'package:orbitx/models/automation_model.dart';
import 'package:intl/intl.dart';

class AutomationBuilderSheet extends StatefulWidget {
  const AutomationBuilderSheet({
    super.key,
  });

  @override
  State<AutomationBuilderSheet> createState() =>
      _AutomationBuilderSheetState();
}

class _AutomationBuilderSheetState
    extends State<AutomationBuilderSheet> {
  final draft = AutomationDraft();

  int page = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * .9,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),

          Container(
            width: 60,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(99),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            "Create Automation",
            style: Theme.of(context)
                .textTheme
                .titleLarge,
          ),

          const SizedBox(height: 12),

          Expanded(
            child: IndexedStack(
              index: page,
              children: [
                _TriggerPage(draft),
                _SchedulePage(draft),
                _ActionPage(draft),
                _ConditionPage(draft),
                _ReviewPage(draft),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (page > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          page--;
                        });
                      },
                      child: const Text(
                        "Back",
                      ),
                    ),
                  ),

                if (page > 0)
                  const SizedBox(width: 12),

                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (page < 4) {
                        setState(() {
                          page++;
                        });
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(
                      page == 4
                          ? "Save"
                          : "Next",
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _TriggerPage extends StatelessWidget {
  final AutomationDraft draft;

  const _TriggerPage(this.draft);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Action"),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          value: draft.action,
          items: AutomationReferences
              .actionTypes
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e),
                ),
              )
              .toList(),
          onChanged: (v) {
            draft.action = v;
          },
        ),
      ],
    );
  }
}

class _SchedulePage extends StatefulWidget {
  final AutomationDraft draft;

  const _SchedulePage(this.draft);

  @override
  State<_SchedulePage> createState() =>
      _SchedulePageState();
}

class _SchedulePageState
    extends State<_SchedulePage> {
  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      initialDate:
          widget.draft.startAt ??
          DateTime.now(),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime:
          widget.draft.startAt != null
              ? TimeOfDay(
                  hour: widget
                      .draft.startAt!.hour,
                  minute: widget
                      .draft.startAt!.minute,
                )
              : TimeOfDay.now(),
    );

    if (time == null) return;

    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      widget.draft.startAt = dateTime;
    });
  }

  String _formatSchedule() {
    final dt = widget.draft.startAt;

    if (dt == null) {
      return "Select Date & Time";
    }

    return DateFormat(
      "dd MMM yyyy • hh:mm a",
    ).format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "Schedule",
          style: Theme.of(context)
              .textTheme
              .titleMedium,
        ),

        const SizedBox(height: 16),

        Card(
          child: ListTile(
            leading:
                const Icon(Icons.schedule),
            title: Text(
              _formatSchedule(),
            ),
            subtitle: const Text(
              "Start Date & Time",
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: _pickDateTime,
          ),
        ),

        const SizedBox(height: 24),

        DropdownButtonFormField<String>(
          value:
              widget.draft.periodicity,
          decoration:
              const InputDecoration(
            labelText: "Periodicity",
            border:
                OutlineInputBorder(),
          ),
          items:
              AutomationReferences
                  .periodicities
                  .map(
                    (e) =>
                        DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
          onChanged: (value) {
            setState(() {
              widget.draft.periodicity =
                  value;
            });
          },
        ),

        const SizedBox(height: 24),

        if (widget.draft.startAt != null)
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const Text(
                    "Summary",
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Text(
                    "Starts: ${DateFormat("dd MMM yyyy").format(widget.draft.startAt!)}",
                  ),

                  Text(
                    "Time: ${DateFormat("hh:mm a").format(widget.draft.startAt!)}",
                  ),

                  Text(
                    "Repeats: ${widget.draft.periodicity ?? "Not Selected"}",
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionPage extends StatefulWidget {
  final AutomationDraft draft;

  const _ActionPage(this.draft);

  @override
  State<_ActionPage> createState() =>
      _ActionPageState();
}

class _ActionPageState
    extends State<_ActionPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount:
                widget.draft.arguments.length,
            itemBuilder: (_, index) {
              final arg = widget
                  .draft.arguments[index];

              return Card(
                margin:
                    const EdgeInsets.all(12),
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),
                  child: Column(
                    children: [
                      DropdownButtonFormField<
                          String>(
                        initialValue: arg.key,
                        items:
                            AutomationReferences
                                .argumentTypes
                                .map(
                                  (e) =>
                                      DropdownMenuItem(
                                    value: e,
                                    child:
                                        Text(
                                      e,
                                    ),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          arg.key = v;
                        },
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      TextFormField(
                        initialValue:
                            arg.value,
                        onChanged: (v) {
                          arg.value = v;
                        },
                        decoration:
                            const InputDecoration(
                          labelText:
                              "Value",
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        Padding(
          padding:
              const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                widget.draft.arguments
                    .add(
                  ArgumentDraft(),
                );
              });
            },
            icon: const Icon(Icons.add),
            label: const Text(
              "Add Argument",
            ),
          ),
        )
      ],
    );
  }
}


class _ConditionPage extends StatelessWidget {
  final AutomationDraft draft;

  const _ConditionPage(this.draft);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value:
              draft.conditionVariable,
          items:
              AutomationReferences
                  .variables
                  .map(
                    (e) =>
                        DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            draft.conditionVariable =
                v;
          },
          decoration:
              const InputDecoration(
            labelText: "Variable",
          ),
        ),

        const SizedBox(height: 12),

        DropdownButtonFormField<String>(
          value:
              draft.conditionOperator,
          items:
              AutomationReferences
                  .operators
                  .map(
                    (e) =>
                        DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ),
                  )
                  .toList(),
          onChanged: (v) {
            draft.conditionOperator =
                v;
          },
          decoration:
              const InputDecoration(
            labelText: "Operator",
          ),
        ),

        const SizedBox(height: 12),

        TextFormField(
          decoration:
              const InputDecoration(
            labelText: "Value",
          ),
          onChanged: (v) {
            draft.conditionValue = v;
          },
        ),
      ],
    );
  }
}

class _ReviewPage extends StatelessWidget {
  final AutomationDraft draft;

  const _ReviewPage(this.draft);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "Action: ${draft.action}",
        ),

        Text(
          "Periodicity: ${draft.periodicity}",
        ),

        Text(
          "Start: ${draft.startAt}",
        ),

        const Divider(),

        const Text(
          "Arguments",
        ),

        ...draft.arguments.map(
          (e) => ListTile(
            title: Text(
              e.key ?? "",
            ),
            subtitle: Text(
              e.value ?? "",
            ),
          ),
        ),

        const Divider(),

        Text(
          "${draft.conditionVariable} "
          "${draft.conditionOperator} "
          "${draft.conditionValue}",
        ),
      ],
    );
  }
}