//! This file adds a tracing subscriber to intercept duplicate message logs and
//! emit them in the specified format.
use slog::Logger;
use tracing::{field::Field, field::Visit, Subscriber};
use tracing_subscriber::layer::{Context, Layer};
use tracing_subscriber::registry::LookupSpan;

// Custom layer to intercept duplicate message logs
pub struct DuplicateMessageLayer {
    stdout_logger: Logger,
}

impl DuplicateMessageLayer {
    pub fn new(stdout_logger: Logger) -> Self {
        Self { stdout_logger }
    }
}

impl<S> Layer<S> for DuplicateMessageLayer
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_event(&self, event: &tracing::Event<'_>, _ctx: Context<'_, S>) {
        let mut message_visitor: Vec<String> = Vec::new();
        struct MessageVisitor<'a>(&'a mut Vec<String>);

        impl<'a> Visit for MessageVisitor<'a> {
            fn record_debug(&mut self, _field: &Field, value: &dyn std::fmt::Debug) {
                self.0.push(format!("{value:?}"));
            }
        }

        event.record(&mut MessageVisitor(&mut message_visitor));

        if message_visitor.len() == 2
            && message_visitor[0].contains("Message already received, ignoring")
        {
            let msg_id_hex_string = &message_visitor[1];
            let bytes = msg_id_hex_string
                .as_bytes()
                .chunks(2)
                .map(|chunk| {
                    let hex_byte = std::str::from_utf8(chunk).unwrap();
                    u8::from_str_radix(hex_byte, 16).unwrap()
                })
                .collect::<Vec<u8>>();

            let msg_id = crate::experiment::format_message_id(&bytes);

            // Emit specified output format.
            slog::info!(self.stdout_logger, "Received Message"; "id" => msg_id);
        }
    }
}

pub fn gossipsub_filter(
) -> tracing_subscriber::filter::FilterFn<impl Fn(&tracing::Metadata<'_>) -> bool> {
    // Create a filter that always allows gossipsub debug events
    tracing_subscriber::filter::filter_fn(|metadata| {
        metadata.target().contains("gossipsub") && *metadata.level() == tracing::Level::DEBUG
    })
}

#[test]
fn test_layer_transforms_duplicate_trace() {
    use libp2p::gossipsub::MessageId;
    use slog::{o, Drain, FnValue, PushFnValue, Record};

    let stdout_drain = slog_json::Json::new(std::io::stdout())
        .add_key_value(o!(
            "time" => FnValue(move |_ : &slog::Record| {
                    time::OffsetDateTime::now_utc()
                    .format(&time::format_description::well_known::Rfc3339)
                    .ok()
            }),
            "level" => FnValue(move |rinfo : &Record| {
                rinfo.level().as_short_str()
            }),
            "msg" => PushFnValue(move |record : &Record, ser| {
                ser.emit(record.msg())
            }),
        ))
        .build()
        .fuse();
    let stdout_drain = slog_async::Async::new(stdout_drain).build().fuse();
    let stdout_logger = slog::Logger::root(stdout_drain, o!());

    use tracing_subscriber::layer::SubscriberExt;

    // Create our custom layer that will process duplicate message events
    let dup_message_layer = DuplicateMessageLayer::new(stdout_logger.clone());

    let subscriber = tracing_subscriber::registry()
        .with(dup_message_layer.with_filter(gossipsub_filter()))
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_ansi(false)
                .with_filter(tracing_subscriber::EnvFilter::from_default_env()),
        );

    tracing::subscriber::set_global_default(subscriber).expect("setting default subscriber failed");

    let msg_id = MessageId::from(0_u64.to_be_bytes());

    // This is what rust-libp2p logs, so we test against this specific message. If rust-libp2p changes we should change this too.
    tracing::debug!(target: "gossipsub", message=%msg_id, "Message already received, ignoring");
}
