import os
import subprocess
import time
from typing import Any

from psycopg import Connection
from psycopg.rows import dict_row
from testcontainers.postgres import PostgresContainer  # type: ignore

from tests.vectorizer.cli.conftest import (
    TestDatabase,
    configure_vectorizer,
    run_vectorizer_worker,
    setup_source_table,
)


def test_worker_no_tasks(cli_db_url: str):
    """Test that worker handles no tasks gracefully"""
    result = run_vectorizer_worker(cli_db_url)

    # It exits successfully
    assert result.exit_code == 0
    assert "no vectorizers found" in result.output.lower()


def test_vectorizer_exits_with_error_when_no_ai_extension(
    postgres_container: PostgresContainer,
):
    result = run_vectorizer_worker(postgres_container.get_connection_url())

    assert result.exit_code == 1
    assert "the pgai extension is not installed" in result.output.lower()


def test_vectorizer_exits_with_error_when_vectorizers_specified_but_missing(
    cli_db_url: str,
):
    result = run_vectorizer_worker(cli_db_url, vectorizer_id=0)
    assert result.exit_code != 0
    assert "invalid vectorizers, wanted: [0], got: []" in result.output


def test_vectorizer_does_not_exit_with_error_when_no_ai_extension(
    postgres_container: PostgresContainer,
):
    result = run_vectorizer_worker(
        postgres_container.get_connection_url(),
        extra_params=["--exit-on-error=false"],
    )

    assert result.exit_code == 0
    assert "the pgai extension is not installed" in result.output.lower()


def test_vectorizer_does_not_exit_with_error_when_vectorizers_specified_but_missing(
    cli_db_url: str,
):
    result = run_vectorizer_worker(
        cli_db_url, vectorizer_id=0, extra_params=["--exit-on-error=false"]
    )
    assert result.exit_code == 0
    assert "invalid vectorizers, wanted: [0], got: []" in result.output


def test_vectorizer_picks_up_new_vectorizer(
    cli_db: tuple[TestDatabase, Connection],
):
    postgres_container, con = cli_db
    db_url = postgres_container.get_connection_url()
    test_env = os.environ.copy()
    test_env["OPENAI_API_KEY"] = (
        "empty"  # the key must be set, but doesn't need to be valid
    )
    process = subprocess.Popen(
        [
            "python",
            "-m",
            "pgai",
            "vectorizer",
            "worker",
            "--db-url",
            db_url,
            "--poll-interval",
            "0.1s",
        ],
        env=test_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )

    # the typings for subprocess.Popen are bad, see https://github.com/python/typeshed/issues/3831
    assert process.stdout is not None

    os.set_blocking(
        process.stdout.fileno(), False
    )  # allow capturing all output without blocking
    count = 0
    while True:
        output = "\n".join(process.stdout.readlines())
        if output != "":
            assert "no vectorizers found" in output
            assert "running vectorizer" not in output
            break
        else:
            # assume that we'll see the output we want to see within 10s
            assert count < 20
            count += 1
            time.sleep(0.5)

    with con.cursor() as cur:
        cur.execute("CREATE TABLE test(id bigint primary key, contents text)")
        cur.execute("""SELECT ai.create_vectorizer('test'::regclass,
            embedding => ai.embedding_openai('text-embedding-3-small', 768),
            chunking => ai.chunking_recursive_character_text_splitter('contents')
        );
        """)
    count = 0
    while True:
        output = "\n".join(process.stdout.readlines())
        if "running vectorizer" not in output:
            # assume that we see the output we want to within 10s
            assert count < 20
            count += 1
            time.sleep(0.5)
        else:
            break
    process.terminate()


def test_recursive_character_splitting(
    cli_db: tuple[PostgresContainer, Connection],
    cli_db_url: str,
    vcr_: Any,
):
    """Test that recursive character splitting correctly chunks
    content based on natural boundaries"""
    _, connection = cli_db
    table_name = setup_source_table(connection, 2)
    vectorizer_id = configure_vectorizer(
        table_name,
        cli_db[1],
        batch_size=2,
        chunking="chunking_recursive_character_text_splitter('content', 100, 20,"
        " separators => array[E'\\n\\n', E'\\n', ' '])",
    )

    # Given content with natural splitting points
    sample_content = """Introduction to Machine Learning

Machine learning is a subset of artificial intelligence that focuses on data and
algorithms.
It enables systems to learn and improve from experience.

Key Concepts:
1. Supervised Learning
2. Unsupervised Learning
3. Reinforcement Learning

Each type has its own unique applications and methodologies."""

    shorter_content = "This is a shorter post that shouldn't need splitting."

    # Update the test data with our structured content
    with connection.cursor(row_factory=dict_row) as cur:
        cur.execute("UPDATE blog SET content = %s WHERE id = 1", (sample_content,))
        cur.execute("UPDATE blog SET content = %s WHERE id = 2", (shorter_content,))

    # When running the worker
    with vcr_.use_cassette("test_recursive_character_splitting.yaml"):
        result = run_vectorizer_worker(cli_db_url, vectorizer_id)

    assert result.exit_code == 0

    # Then verify the chunks were created correctly
    with connection.cursor(row_factory=dict_row) as cur:
        cur.execute("""
            SELECT id, chunk_seq, chunk
            FROM blog_embedding_store
            ORDER BY id, chunk_seq
        """)
        chunks = cur.fetchall()

        # Verify we got multiple chunks for the longer content
        first_doc_chunks = [c for c in chunks if c["id"] == 1]
        assert (
            len(first_doc_chunks) > 1
        ), "Long document should be split into multiple chunks"

        # Verify chunk boundaries align with natural breaks
        assert any(
            "Introduction to Machine Learning" in c["chunk"] for c in first_doc_chunks
        ), "Should have a chunk starting with the title"

        assert not all(
            "Introduction to Machine Learning" in c["chunk"] for c in first_doc_chunks
        ), "Not all chunks should start with the title"

        assert any(
            "Key Concepts:" in c["chunk"] for c in first_doc_chunks
        ), "Should have a chunk containing the key concepts section"

        # Verify shorter content remains as single chunk
        second_doc_chunks = [c for c in chunks if c["id"] == 2]
        assert len(second_doc_chunks) == 1, "Short document should be a single chunk"
        assert second_doc_chunks[0]["chunk"] == shorter_content

        # Verify chunk sequences are correct
        for doc_chunks in [first_doc_chunks, second_doc_chunks]:
            sequences = [c["chunk_seq"] for c in doc_chunks]
            assert sequences == list(
                range(len(sequences))
            ), "Chunk sequences should be sequential starting from 0"
