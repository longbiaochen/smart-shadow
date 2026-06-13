#!/usr/bin/env bash
set -euo pipefail

db_path="${SMART_SHADOW_MAIL_ENVELOPE_INDEX:-$HOME/Library/Mail/V10/MailData/Envelope Index}"
limit="${SMART_SHADOW_MAIL_EXPORT_LIMIT:-50}"

if [[ ! "$limit" =~ ^[0-9]+$ ]]; then
  echo "SMART_SHADOW_MAIL_EXPORT_LIMIT must be numeric" >&2
  exit 64
fi

if [[ ! -r "$db_path" ]]; then
  echo "Apple Mail Envelope Index is not readable: $db_path" >&2
  exit 66
fi

/usr/bin/sqlite3 -json "$db_path" "
with unread_inbox as (
  select
    m.rowid as rowid,
    trim(coalesce(nullif(g.message_id_header, ''), cast(m.message_id as text)), '<>') as source_id,
    coalesce(nullif(a.comment, ''), a.address, '(unknown sender)') as sender_name,
    coalesce(a.address, '(unknown sender)') as sender_address,
    coalesce(s.subject, '(no subject)') as subject,
    coalesce(mb.url, 'INBOX') as mailbox_url,
    m.date_received as date_received
  from messages m
  left join message_global_data g on g.rowid = m.global_message_id
  left join addresses a on a.rowid = m.sender
  left join subjects s on s.rowid = m.subject
  left join mailboxes mb on mb.rowid = m.mailbox
  where m.deleted = 0
    and m.read = 0
    and mb.url like '%/INBOX'
)
select
  cast(max(rowid) as text) as source_id,
  'apple_mail:' || source_id as canonical_key,
  source_id as message_id_header,
  case
    when sender_name = sender_address then sender_address
    else sender_name || ' <' || sender_address || '>'
  end as sender,
  subject,
  'INBOX' as mailbox,
  strftime('%Y-%m-%dT%H:%M:%SZ', max(date_received), 'unixepoch') as received_at,
  'Apple Mail unread inbox metadata only. Body was not read by this source.' as summary
from unread_inbox
where source_id is not null and source_id != ''
group by source_id
order by max(date_received) desc
limit $limit;
"
